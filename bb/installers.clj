(ns installers
  "Keeps a local copy of each packaged installer in installers/, which Git ignores.

  Microchip serves some installers only after a login, so fetchurl cannot download them again
  after garbage collection. `save` copies the installers that are in the store into the folder;
  `import` adds the folder's files back to the store as the fixed-output paths that the packages
  expect."
  (:require [babashka.fs :as fs]
            [babashka.process :as process]
            [cheshire.core :as json]
            [clojure.string :as str]))

(def cache-dir "installers")

(def attribute-pattern "(xc8|xc16|xc32|xc-dsc|mplab-x-unwrapped)_[0-9_]+")

(defn- shell [& args]
  (apply process/shell {:out :string :err :string :continue true} args))

(defn inventory
  "Returns a map from package attribute to {:name :path} of its installer source, from the flake in
  the current directory. Evaluates only: it downloads and builds nothing."
  []
  (let [expr (str "p: builtins.listToAttrs (map (n: { name = n; value = { name = p.${n}.src.name;"
                  " path = p.${n}.src.outPath; }; }) (builtins.filter (n: builtins.match \""
                  attribute-pattern "\" n != null) (builtins.attrNames p)))")
        {:keys [exit out err]} (shell "nix" "eval" "--json" ".#legacyPackages.x86_64-linux"
                                      "--apply" expr)]
    (when-not (zero? exit)
      (throw (ex-info "Cannot evaluate the packaged installers." {:error err})))
    (update-vals (json/parse-string out) #(update-keys % keyword))))

(defn valid-path? [path]
  (zero? (:exit (shell "nix-store" "--check-validity" path))))

(defn cached-names []
  (if (fs/directory? cache-dir)
    (set (map (comp str fs/file-name) (fs/list-dir cache-dir)))
    #{}))

(defn plan
  "Returns the actions for `command` (:save or :import). `installers` maps attribute to {:name
  :path}; `in-store?` is a predicate on store paths; `cached` is the set of file names in the
  cache. Several attributes can share one installer, so each action is for one installer name."
  [command installers in-store? cached]
  (let [by-name (vals (into (sorted-map) (map (fn [[_ v]] [(:name v) v]) installers)))
        known (set (map :name by-name))]
    (case command
      :save (for [{:keys [name path]} by-name
                  :when (and (not (cached name)) (in-store? path))]
              {:action :copy :name name :path path})
      :import (concat
               (for [{:keys [name path]} by-name
                     :when (and (cached name) (not (in-store? path)))]
                 {:action :add :name name :path path})
               (for [name (sort cached) :when (not (known name))]
                 {:action :unknown :name name})))))

(defn status-rows [installers in-store? cached]
  (for [[attr {:keys [name path]}] (sort installers)]
    [attr (if (in-store? path) "store" "-") (if (cached name) "cached" "-") name]))

(defn- add-to-store!
  "Adds the cached file to the store, and throws if the result is not the expected path (the file
  does not match the pinned hash)."
  [{:keys [name path]}]
  (let [{:keys [exit out err]} (shell "nix-store" "--add-fixed" "sha256"
                                      (str (fs/path cache-dir name)))
        added (str/trim out)]
    (cond
      (not (zero? exit)) (throw (ex-info (str "Cannot add " name " to the store.") {:error err}))
      (not= added path) (throw (ex-info (str name " does not match its pinned hash: got " added
                                             ", expected " path ".") {}))
      :else (println "added" path))))

(defn run [command]
  (let [installers (inventory)
        in-store? (memoize valid-path?)
        cached (cached-names)]
    (case command
      :status (doseq [row (status-rows installers in-store? cached)]
                (println (str/join " " row)))
      :save (do (fs/create-dirs cache-dir)
                (doseq [{:keys [name path]} (plan :save installers in-store? cached)]
                  (fs/copy path (fs/path cache-dir name))
                  (println "saved" name)))
      :import (doseq [{:keys [action name] :as step} (plan :import installers in-store? cached)]
                (case action
                  :add (add-to-store! step)
                  :unknown (println "skipped" name "(no packaged installer has this name)"))))))

(defn parse-args [args]
  (case (vec args)
    [] :status
    ["status"] :status
    ["save"] :save
    ["import"] :import
    (throw (ex-info "Usage: bb installers [status|save|import]" {}))))

(defn main [& args]
  (try
    (run (parse-args args))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [stderr (:error (ex-data error))]
          (println stderr)))
      (System/exit 1))))
