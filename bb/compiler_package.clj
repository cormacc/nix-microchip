(ns compiler-package
  (:require [babashka.fs :as fs]
            [babashka.process :as process]
            [clojure.string :as str]
            [project-config :as project])
  (:import [java.net URI]))

(def usage
  (str "Usage: bb package --url <https-linux-installer-url> [--family <family>] [--version <version>]\n"
       "       bb package --file <linux-installer-file> [--family <family>] [--version <version>]\n"
       "       bb package --family <xc8|xc16|xc32|xc-dsc> --version <version>\n"
       "       [--write] [--verify]\n\n"
       "Default: download/hash the installer and preview the package and registration.\n"
       "--file hashes a downloaded installer that needs a Microchip login, adds it to the store\n"
       "and marks the package loginRequired.\n"
       "--verify builds a temporary candidate and checks version, compile/link and licence diagnostics.\n"
       "--write adds source files, after verification if requested. Never changes defaults or Git staging."))

(def families #{"xc8" "xc16" "xc32" "xc-dsc"})

(defn parse-args [args]
  (if (= ["--help"] (vec args))
    {:help? true}
    (loop [args args result {} seen #{}]
      (if-let [flag (first args)]
        (let [key (get {"--url" :url "--file" :file "--family" :family "--version" :version
                       "--write" :write? "--verify" :verify?} flag)
              boolean? (#{:write? :verify?} key)
              value (second args)]
          (when-not key (throw (ex-info (str "Unknown option: " flag "\n" usage) {})))
          (when (contains? seen key) (throw (ex-info (str "Repeated option: " flag) {})))
          (when (and (not boolean?) (or (str/blank? value) (str/starts-with? value "--")))
            (throw (ex-info (str "Missing value for " flag) {})))
          (recur (if boolean? (next args) (nnext args))
                 (assoc result key (if boolean? true value)) (conj seen key)))
        result))))

(defn legacy-xc16? [family version]
  (let [[major minor] (mapv bigint (take 2 (str/split version #"\.")))]
    (and (= "xc16" family) (or (< major 1) (and (= major 1) (< minor 50))))))

(defn installer-details [{:keys [url file family version] :as options}]
  (when (and url file) (throw (ex-info "Use --url or --file, not both" {})))
  (when (and file (not (fs/regular-file? file)))
    (throw (ex-info (str "Installer file not found: " file) {})))
  (let [uri (when url (URI. url))
        _ (when (and uri (or (not= "https" (.getScheme uri))
                             (nil? (.getHost uri)) (.getUserInfo uri)
                             (.getRawQuery uri) (.getRawFragment uri)))
            (throw (ex-info "Use an HTTPS installer URL without credentials, query or fragment" {})))
        filename (cond uri (last (str/split (.getPath uri) #"/"))
                       file (str (fs/file-name file)))
        [_ url-family url-version]
        (when filename (re-find #"(?i)^(xc8|xc16|xc32|xc-dsc)-v([0-9]+(?:\.[0-9]+)+)-" filename))
        family (some-> (or family url-family) str/lower-case)
        version (or version url-version)]
    (when-not (contains? families family)
      (throw (ex-info (str "Specify --family xc8, xc16, xc32 or xc-dsc\n" usage) {})))
    (when-not (and version (re-matches #"[0-9]+(?:\.[0-9]+)+" version))
      (throw (ex-info "Specify a numeric --version, e.g. 1.61" {})))
    (when (and url-family (not= family (str/lower-case url-family)))
      (throw (ex-info "--family disagrees with the installer filename" {})))
    (when (and url-version (not= version url-version))
      (throw (ex-info "--version disagrees with the installer filename" {})))
    (when filename
      (let [lower (str/lower-case filename)
            legacy? (legacy-xc16? family version)
            expected (if legacy? ".run.tar" ".run")
            layout (if legacy?
                     #"(?:^|[-_])linux(?:32|[-_](?:i[3-6]86|x86))?-installer[.]run[.]tar$"
                     #"(?:^|[-_])linux(?:64|[-_](?:x64|x86_64|amd64))-installer[.]run$")]
        (when (or (not (re-find layout lower))
                  (re-find #"windows|win32|win64|darwin|osx|macos" lower))
          (throw (ex-info (str "Unsupported installer layout: expected an x86 Linux " expected
                               "; shared packaging logic needs review") {})))))
    (assoc options :family family :version version
           :attribute (str family "_" (str/replace version "." "_")))))

(defn version-source [{:keys [version url file]} hash]
  (str "import ./common.nix {\n  version = " (project/nix-string version) ";\n"
       "  hash = " (project/nix-string hash) ";\n"
       (when url (str "  url = " (project/nix-string url) ";\n"))
       (when file "  loginRequired = true;\n") "}\n"))

(defn registration [registry {:keys [family version attribute]}]
  (let [entry-re (re-pattern (str "(?m)^\\s*" attribute "\\s*="))
        anchor-re (re-pattern (str "(?m)^([ \\t]*)" family "_[0-9_]+[ \\t]*="))
        anchor (re-find anchor-re registry)]
    (when-not anchor
      (throw (ex-info "Cannot find the compiler family's registration block; review pkgs/default.nix" {})))
    (let [[matched indent] anchor
          line (str indent attribute " = pkgs.callPackage ./" family "/" version
                    ".nix { inherit microchip-xclm-license; };\n")
          offset (str/index-of registry matched)]
      {:line line :registered? (boolean (re-find entry-re registry))
       :candidate (str (subs registry 0 offset) line (subs registry offset))})))

(defn write-check! [root {:keys [family version registered?]} original-registry]
  (when (or registered?
            (fs/exists? (str root "/pkgs/" family "/" version ".nix") {:nofollow-links true}))
    (throw (ex-info "This compiler version already exists; refusing to overwrite it" {})))
  (when (or (fs/exists? (str root "/pkgs/.#default.nix") {:nofollow-links true})
            (not= original-registry (slurp (str root "/pkgs/default.nix"))))
    (throw (ex-info "pkgs/default.nix is locked or changed; review it and retry" {}))))

(defn source-expression
  "Returns a Nix expression for the candidate package's installer source. Without `hash`, the
  source has a fake hash, so that building it reports the real one. With `hash`, the source is a
  login-required one, and the expression gives its store path."
  ([root details] (source-expression root details nil))
  ([root {:keys [family version url]} hash]
   (str "let f = builtins.getFlake " (project/nix-string (project/flake-uri root)) ";\n"
        "p = import f.inputs.nixpkgs { system = \"x86_64-linux\"; config.allowUnfree = true; };\n"
        "compiler = p.callPackage (import "
        (project/nix-string (str root "/pkgs/" family "/common.nix"))
        " { version = " (project/nix-string version) "; hash = "
        (if hash (project/nix-string hash) "f.inputs.nixpkgs.lib.fakeHash") ";"
        (when hash " loginRequired = true;")
        (when url (str " url = " (project/nix-string url) ";")) " })\n"
        "{ inherit (f.legacyPackages.x86_64-linux) microchip-xclm-license; };\n"
        (if hash "in compiler.src.outPath" "in compiler.src"))))

(defn installer-hash [root details]
  ;; Only the fixed-output source is realised; hashing never executes the installer.
  (let [{:keys [exit err]} (project/nix-result "build" "--impure" "--no-link" "--print-out-paths"
                                             "--expr" (source-expression root details))
        [_ hash] (re-find #"got:\s+(sha256-[A-Za-z0-9+/]{43}=)" err)]
    (if (and (not (zero? exit)) hash)
      hash
      (throw (ex-info "Cannot download/hash the installer; no package files were written" {:error err})))))

(defn add-to-store [file]
  (process/shell {:out :string :err :string :continue true}
                 "nix-store" "--add-fixed" "sha256" (str file)))

(defn local-installer-hash
  "Returns the hash of a downloaded installer, after adding it to the store. Throws if the store
  path differs from the one that the candidate package expects, i.e. the file name is not the
  family's installer name for this version. Never executes the installer."
  [root {:keys [file] :as details}]
  (let [{:keys [exit out err]} (project/nix-result "hash" "file" "--sri" "--type" "sha256" (str file))
        _ (when-not (zero? exit) (throw (ex-info "Cannot hash the installer file" {:error err})))
        hash (str/trim out)
        expected (project/nix-result "eval" "--impure" "--raw" "--expr"
                                     (source-expression root details hash))
        _ (when-not (zero? (:exit expected))
            (throw (ex-info "Cannot evaluate the candidate installer source" {:error (:err expected)})))
        added (add-to-store file)]
    (when-not (zero? (:exit added))
      (throw (ex-info "Cannot add the installer file to the store" {:error (:err added)})))
    (when-not (= (str/trim (:out expected)) (str/trim (:out added)))
      (throw (ex-info (str "The file name is not the package's installer name: added "
                           (str/trim (:out added)) ", expected " (str/trim (:out expected))) {})))
    hash))

(defn verify! [root {:keys [family version]} content]
  (fs/create-dirs (str root "/.tmp"))
  (let [scratch (str (fs/create-temp-dir {:dir (str root "/.tmp") :prefix "package-verify-"}))
        ;; Mirror pkgs/: common.nix imports ../login-installer.nix for a loginRequired version.
        family-dir (str scratch "/" family)
        candidate (str family-dir "/candidate.nix")]
    (try
      (fs/create-dirs family-dir)
      (spit candidate content)
      (fs/copy (str root "/pkgs/" family "/common.nix") (str family-dir "/common.nix"))
      (fs/copy (str root "/pkgs/login-installer.nix") (str scratch "/login-installer.nix"))
      (let [{:keys [exit out]} (process/shell
                               {:out :string :err :inherit :continue true}
                               "nix" "build" "--impure" "--no-link" "--print-out-paths"
                               "--file" (str root "/bb/package_verify.nix")
                               "--argstr" "flakeUri" (project/flake-uri root)
                               "--argstr" "candidate" candidate
                               "--argstr" "family" family "--argstr" "version" version)]
        (when-not (zero? exit)
          (throw (ex-info "Verification failed; review installer layout, flags, device support and licence behaviour" {})))
        (binding [*out* *err*] (println "Verification passed:" (str/trim out))))
      (finally (fs/delete-tree scratch)))))

(defn write-files! [root details original-registry candidate-registry content]
  (write-check! root details original-registry)
  (fs/create-dirs (str root "/.tmp"))
  (let [scratch (str (fs/create-temp-dir {:dir (str root "/.tmp") :prefix "package-write-"}))
        temporary-registry (str scratch "/default.nix")
        target (str root "/pkgs/" (:family details) "/" (:version details) ".nix")]
    (try
      (fs/copy (str root "/pkgs/default.nix") temporary-registry {:copy-attributes true})
      (spit temporary-registry candidate-registry)
      ;; CREATE_NEW also refuses a dangling symlink or a concurrently created version file.
      (fs/create-file target)
      (try
        (spit target content)
        (when (or (fs/exists? (str root "/pkgs/.#default.nix") {:nofollow-links true})
                  (not= original-registry (slurp (str root "/pkgs/default.nix"))))
          (throw (ex-info "pkgs/default.nix changed while preparing the package" {})))
        (fs/move temporary-registry (str root "/pkgs/default.nix")
                 {:replace-existing true :atomic-move true})
        (catch Exception error
          (when (= content (slurp target)) (fs/delete target))
          (throw error)))
      (finally (fs/delete-tree scratch)))))

(defn scaffold! [root details]
  (let [registry (slurp (str root "/pkgs/default.nix"))
        {:keys [line candidate registered?]} (registration registry details)
        details (assoc details :registered? registered?)]
    (when (:write? details) (write-check! root details registry))
    (let [hash ((if (:file details) local-installer-hash installer-hash) root details)
          content (version-source details hash)
          relative (str "pkgs/" (:family details) "/" (:version details) ".nix")]
      (println (str (if (:write? details) "Package candidate: " "Dry run: ") relative))
      (print content)
      (when (or registered? (fs/exists? (str root "/" relative) {:nofollow-links true}))
        (println "Existing package: preview/verification only; --write would refuse."))
      (println "Registration in pkgs/default.nix:")
      (print line)
      (when (:verify? details) (verify! root details content))
      (if (:write? details)
        (do (write-files! root details registry candidate content)
            (println "Written; default versions and Git staging are unchanged.")
            (when-not (:verify? details)
              (println "Not compile/link verified; run again without --write and with --verify to check it."))
            (println (str "Stage the new file before Git-flake evaluation: git add " relative " pkgs/default.nix")))
        (println "No package files changed. Use --write to add them; existing versions cannot be overwritten.")))))

(defn main [& args]
  (try
    (let [options (parse-args args)]
      (if (:help? options)
        (println usage)
        (let [details (installer-details options)]
          (scaffold! (project/flake-root) details))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [stderr (:error (ex-data error))] (println stderr)))
      (System/exit 1))))
