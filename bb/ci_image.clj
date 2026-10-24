(ns ci-image
  (:require [babashka.fs :as fs]
            [babashka.process :as process]
            [cheshire.core :as json]
            [clojure.string :as str]
            [project-config :as project]))

(def usage
  (str "Usage: bb ci-image --project <directory-or-configurations.xml>\n"
       "                   [--configuration <name>] [--name <image-repository>]\n"
       "       bb ci-image --compiler <xc16_1_61> [--compiler <attribute> ...]\n"
       "                   [--pack <vendor/name/version> ...] [--name <image-repository>]\n\n"
       "Builds an MPLAB-capable image and prints its stream script path.\n"
       "Run the script to write a Docker image archive to stdout; loading and publishing are separate.\n"
       "The default image repository is xc-cli; its tag is content-derived."))

(def ^:private options
  {"--project" :project "--configuration" :configuration "--name" :name
   "--compiler" :compilers "--pack" :packs})

(defn- image-name? [value]
  (let [component "[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*"
        registry "[a-z0-9]+(?:[.-][a-z0-9]+)*(?::[0-9]+)?"]
    (boolean (re-matches (re-pattern (str "(?:" registry "/)?"
                                         component "(?:/" component ")*")) value))))

(defn parse-args [args]
  (if (= ["--help"] (vec args))
    {:help? true}
    (let [parsed
          (loop [args args result {:name "xc-cli" :compilers [] :packs []} seen #{}]
            (if-let [flag (first args)]
              (let [key (get options flag)
                    value (second args)
                    repeated? (#{:compilers :packs} key)]
                (when-not key
                  (throw (ex-info (str "Unknown option: " flag "\n" usage) {})))
                (when (or (str/blank? value) (str/starts-with? value "--"))
                  (throw (ex-info (str "Missing value for " flag) {})))
                (when (and (not repeated?) (contains? seen key))
                  (throw (ex-info (str "Repeated option: " flag) {})))
                (recur (nnext args)
                       (if repeated? (update result key conj value)
                           (assoc result key value))
                       (conj seen key)))
              result))]
      (when-not (image-name? (:name parsed))
        (throw (ex-info "--name must be a lowercase image repository, without a tag or digest" {})))
      (when (and (:project parsed) (or (seq (:compilers parsed)) (seq (:packs parsed))))
        (throw (ex-info "--project cannot be combined with --compiler or --pack" {})))
      (when (and (:configuration parsed) (not (:project parsed)))
        (throw (ex-info "--configuration requires --project" {})))
      (when-not (or (:project parsed) (seq (:compilers parsed)))
        (throw (ex-info usage {})))
      parsed)))

(defn select-configuration [configurations requested]
  (let [names (mapv #(get-in % [:attrs :name]) configurations)
        available (str/join ", " names)]
    (when (empty? configurations)
      (throw (ex-info "The project has no build configurations" {})))
    (when (some str/blank? names)
      (throw (ex-info "The project has an unnamed build configuration" {})))
    (let [matches (if requested
                    (filter #(= requested (get-in % [:attrs :name])) configurations)
                    configurations)]
      (if (= 1 (count matches))
        (first matches)
        (throw (ex-info (str "Select one --configuration; available: " available) {}))))))

(defn- compiler-attribute [attribute]
  (if-let [[_ family version]
           (re-matches #"(xc8|xc16|xc32|xc-dsc)_([0-9]+(?:_[0-9]+)+)" attribute)]
    (project/compiler-attribute family (str/replace version "_" "."))
    (throw (ex-info (str "Use a versioned compiler attribute, e.g. xc16_1_61: " attribute) {}))))

(defn validate-pack [{:keys [vendor name version] :as pack}]
  (when-not (and (string? vendor) (re-matches #"[A-Za-z0-9_][A-Za-z0-9_.+-]*" vendor)
                 (string? name) (re-matches #"[A-Za-z0-9_][A-Za-z0-9_.+-]*" name)
                 (string? version) (re-matches #"[0-9][A-Za-z0-9_.+-]*" version))
    (throw (ex-info (str "Pack must specify vendor/name/version: " (pr-str pack)) {})))
  pack)

(defn- parse-pack [value]
  (let [parts (str/split value #"/" -1)]
    (when-not (= 3 (count parts))
      (throw (ex-info (str "Pack must specify vendor/name/version: " value) {})))
    (validate-pack (zipmap [:vendor :name :version] parts))))

(defn selection [root {:keys [project configuration compilers packs name]}]
  (let [conf (when project
               (select-configuration (project/project-configurations project) configuration))
        compilers (if conf
                    [(project/compiler-attribute
                      (project/element-text conf :languageToolchain)
                      (project/element-text conf :languageToolchainVersion))]
                    (mapv compiler-attribute compilers))
        packs (if conf
                (mapv validate-pack (project/configuration-packs conf))
                (mapv parse-pack packs))]
    {:name name
     :compilers (vec (distinct compilers))
     :packs (mapv #(assoc % :hash (project/pack-hash root %)) (distinct packs))}))

(defn image-expression [root selection-file]
  (str "let\n"
       "  flake = builtins.getFlake " (project/nix-string (project/flake-uri root)) ";\n"
       "  mc = flake.legacyPackages.x86_64-linux;\n"
       "  selection = builtins.fromJSON (builtins.readFile " (project/nix-string selection-file) ");\n"
       "  xc-cli = mc.xc-cli.override {\n"
       "    compilers = map (name: builtins.getAttr name mc) selection.compilers;\n"
       "    packs = map mc.fetchMplabPack selection.packs;\n"
       "    withMplabProjects = true;\n"
       "  };\n"
       "in mc.mkCiImage { inherit xc-cli; name = selection.name; }\n"))

(defn build-image! [root selected]
  (fs/create-dirs (str root "/.tmp"))
  (let [scratch (str (fs/create-temp-dir {:dir (str root "/.tmp") :prefix "ci-image-"}))
        selection-file (str scratch "/selection.json")
        expression-file (str scratch "/image.nix")]
    (try
      (spit selection-file (json/generate-string selected))
      (spit expression-file (image-expression root selection-file))
      (let [{:keys [exit out]}
            (process/shell {:out :string :err :inherit :continue true}
                           "nix" "build" "--impure" "--file" expression-file
                           "--no-link" "--print-out-paths")]
        (when-not (zero? exit)
          (throw (ex-info (str "Cannot build CI image (exit " exit ")") {})))
        (str/trim out))
      (finally (fs/delete-tree scratch)))))

(defn main [& args]
  (try
    (let [options (parse-args args)]
      (if (:help? options)
        (println usage)
        (let [root (project/flake-root)]
          (println (build-image! root (selection root options))))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [stderr (:error (ex-data error))]
          (println stderr)))
      (System/exit 1))))
