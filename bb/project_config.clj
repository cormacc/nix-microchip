(ns project-config
  (:require [babashka.process :as process]
            [cheshire.core :as json]
            [clojure.data.xml :as xml]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(def toolchain-prefixes
  {"xc8" "xc8"
   "xc16" "xc16"
   "xc32" "xc32"
   "xc-dsc" "xc-dsc"})

(defn command-result [& args]
  (apply process/shell {:out :string :err :string :continue true} args))

(defn nix-result [& args]
  (apply command-result "nix" args))

(defn elements [element]
  (tree-seq map? :content element))

(defn first-element [element tag]
  (first (filter #(= tag (:tag %)) (elements element))))

(defn element-text [element tag]
  (->> (first-element element tag)
       :content
       (filter string?)
       (apply str)
       str/trim))

(defn nix-string
  "Quotes `value` as a Nix string without enabling string interpolation."
  [value]
  (str/replace (json/generate-string (str value)) "${" "\\${"))

(defn project-configurations
  "Reads configurations from a project directory or configurations.xml file."
  [project]
  (let [path (io/file project)
        path (if (.isDirectory path)
               (io/file path "nbproject" "configurations.xml")
               path)]
    (when-not (.isFile path)
      (throw (ex-info (str "MPLAB configurations file not found: " path) {})))
    (with-open [reader (io/reader path)]
      (let [document (xml/parse reader :namespace-aware false :location-info false)]
        (doall (filter #(= :conf (:tag %)) (elements document)))))))

(defn packaged-attributes [prefix]
  (let [pattern (str prefix "_[0-9_]+")
        apply-expression (str "attrs: builtins.filter (n: builtins.match " (pr-str pattern) " n != null) (builtins.attrNames attrs)")
        {:keys [exit out err]} (nix-result "eval" "--json" "--apply" apply-expression ".#legacyPackages.x86_64-linux")]
    (if (zero? exit)
      (json/parse-string out)
      (throw (ex-info "Cannot list packaged compiler versions." {:error err})))))

(defn compiler-attribute [toolchain version]
  (let [prefix (get toolchain-prefixes (str/lower-case toolchain))
        attribute (str prefix "_" (str/replace version "." "_"))]
    (when-not prefix
      (throw (ex-info (str "Unsupported language toolchain: " toolchain) {})))
    (let [available (packaged-attributes prefix)]
      (if (some #{attribute} available)
        attribute
        (throw (ex-info (str "Toolchain " toolchain " " version " is not packaged; packaged " prefix " versions: " (str/join ", " (map #(str/replace (subs % (inc (count prefix))) "_" ".") available)) ".") {}))))))

(defn flake-root []
  (let [{:keys [exit out err]} (command-result "git" "rev-parse" "--show-toplevel")]
    (if (zero? exit)
      (str/trim out)
      (throw (ex-info "Cannot resolve the flake root." {:error err})))))

(defn flake-uri [root]
  (str "git+file://" (.getRawPath (.toURI (io/file root)))))

(defn pack-hash [root {:keys [vendor name version]}]
  (let [expression (str "let flake = builtins.getFlake " (nix-string (flake-uri root)) "; in flake.legacyPackages.x86_64-linux.fetchMplabPack { vendor = " (nix-string vendor) "; name = " (nix-string name) "; version = " (nix-string version) "; hash = flake.inputs.nixpkgs.lib.fakeHash; }")
        {:keys [exit err]} (nix-result "build" "--impure" "--no-link" "--print-out-paths" "--expr" expression)
        [_ hash] (re-find #"got:\s+(sha256-[A-Za-z0-9+/]{43}=)" err)]
    (if (and (not (zero? exit)) hash)
      hash
      (throw (ex-info "Cannot calculate the MPLAB pack hash." {:error err})))))

(defn configuration-packs [configuration]
  (map #(select-keys (:attrs %) [:vendor :name :version])
       (filter #(= :pack (:tag %)) (elements configuration))))

(defn nix-pack [{:keys [vendor name version hash]}]
  (str "(pkgs.fetchMplabPack { name = " (nix-string name) "; version = " (nix-string version) "; hash = " (nix-string hash) ";"
       (when (not= vendor "Microchip") (str " vendor = " (nix-string vendor) ";"))
       " })"))

(defn nix-block [compiler packs]
  (str "pkgs.xc-cli.override { compilers = [ pkgs." compiler " ]; packs = [ " (str/join " " (map nix-pack packs)) " ]; }"))

(defn main [& args]
  (try
    (when-not (= 1 (count args))
      (throw (ex-info "Usage: bb project-config <project-directory-or-configurations.xml>" {})))
    (let [root (flake-root)
          hash-for (memoize #(pack-hash root %))]
      (doseq [configuration (project-configurations (first args))]
        (let [toolchain (element-text configuration :languageToolchain)
              version (element-text configuration :languageToolchainVersion)
              compiler (compiler-attribute toolchain version)
              packs (map #(assoc % :hash (hash-for %)) (configuration-packs configuration))]
          (println (str "# " (get-in configuration [:attrs :name])))
          (println (nix-block compiler packs)))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [stderr (:error (ex-data error))]
          (println stderr)))
      (System/exit 1))))
