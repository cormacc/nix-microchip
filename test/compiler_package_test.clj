(ns compiler-package-test
  (:require [babashka.fs :as fs]
            [babashka.process :as process]
            [clojure.string :as str]
            [clojure.test :refer [deftest is use-fixtures]]
            [compiler-package :as package]
            [project-config :as project]))

(def ^:dynamic *root* nil)
(def hash-value "sha256-Wi0vhJWt+WiNq41daf7e7tJeJmt3/M3t2TJbkJQTNEg=")
(def registry
  (str "pkgs: rec {\n"
       "   xc16_1_61 = pkgs.callPackage ./xc16/1.61.nix { inherit microchip-xclm-license; };\n"
       "   xc16 = xc16_1_61; # default stays unchanged\n}\n"))

(use-fixtures :each
  (fn [run-test]
    (fs/create-dirs ".tmp")
    (binding [*root* (str (fs/absolutize (fs/create-temp-dir {:dir ".tmp" :prefix "package-test-"}))) ]
      (try
        (fs/create-dirs (str *root* "/pkgs/xc16"))
        (spit (str *root* "/pkgs/default.nix") registry)
        (spit (str *root* "/pkgs/xc16/common.nix") "{ version, hash, url ? null }: { lib }: {}\n")
        (run-test)
        (finally (fs/delete-tree *root*))))))

(defn details [& args]
  (package/installer-details (package/parse-args args)))

(deftest parse-options-test
  (is (= {:help? true} (package/parse-args ["--help"])))
  (is (= {:family "xc16" :version "1.62" :write? true :verify? true}
         (package/parse-args ["--family" "xc16" "--version" "1.62" "--write" "--verify"])))
  (doseq [args [["--bad"] ["--family" "xc16" "--bad"] ["--url"]
                ["--version" "--write"] ["--verify" "--verify"]
                ["--family" "xc16" "--family" "xc8"]]]
    (is (thrown? clojure.lang.ExceptionInfo (package/parse-args args)) (pr-str args))))

(deftest infer-family-and-version-test
  (doseq [[family version suffix] [["xc16" "1.61" "full-install-linux64-installer.run"]
                                   ["xc16" "1.21" "linux-installer.run.tar"]
                                   ["xc8" "4.00" "full-install-linux-x64-installer.run"]
                                   ["xc32" "6.00" "full-install-linux-x64-installer.run"]
                                   ["xc-dsc" "4.00" "full-install-linux64-installer.run"]]]
    (let [selected (details "--url" (str "https://example.test/" family "-v" version "-" suffix))]
      (is (= family (:family selected)))
      (is (= version (:version selected)))
      (is (= (str family "_" (str/replace version "." "_")) (:attribute selected)))))
  (is (= "xc16" (:family (details "--family" "XC16" "--version" "1.62"))))
  (is (= "1.62" (:version (details "--url" "https://example.test/compiler-linux64-installer.run"
                                   "--family" "xc16" "--version" "1.62")))))

(deftest rejected-identifiers-test
  (doseq [args [[] ["--family" "arm" "--version" "1.0"]
                ["--family" "xc16"] ["--family" "xc16" "--version" "1_61"]
                ["--url" "https://example.test/xc16-v1.61-full-install-linux64-installer.run"
                 "--family" "xc8"]
                ["--url" "https://example.test/xc16-v1.61-full-install-linux64-installer.run"
                 "--version" "1.62"]]]
    (is (thrown? clojure.lang.ExceptionInfo
                 (package/installer-details (package/parse-args args))) (pr-str args))))

(deftest rejected-downloads-test
  (doseq [url ["http://example.test/xc16-v1.61-full-install-linux64-installer.run"
               "https://user:password@example.test/xc16-v1.61-full-install-linux64-installer.run"
               "https://example.test/xc16-v1.61-full-install-linux64-installer.run?token=secret"
               "https://example.test/xc16-v1.61-full-install-linux64-installer.run#part"
               "https://example.test/xc16-v1.61-windows-installer.exe"
               "https://example.test/xc16-v1.61-linux-arm64-installer.run"
               "https://example.test/xc32-v6.00-linux-ppc64-installer.run"
               "https://example.test/xc32-v6.00-linux-riscv64-installer.run"
               "https://example.test/xc16-v1.61-linux-installer.run"
               "https://example.test/xc16-v1.21-linux64-installer.run.tar"
               "https://example.test/xc16-v1.21-linux-installer.run"
               "https://example.test/xc16-v1.50-linux-installer.run.tar"
               "https://example.test/xc16-v1.61-linux32-installer.run"
               "https://example.test/xc32-v6.00-linux-installer.zip"]]
    (is (thrown? clojure.lang.ExceptionInfo (details "--url" url)) url)))

(deftest legacy-boundary-test
  (doseq [[version expected] [["1.21" true] ["1.49.9" true] ["1.50" false]
                              ["1.50.1" false] ["2.10" false]]]
    (is (= expected (package/legacy-xc16? "xc16" version))))
  (is (false? (package/legacy-xc16? "xc8" "1.21"))))

(deftest source-and-registration-test
  (let [selected (details "--family" "xc16" "--version" "1.62")
        plan (package/registration registry selected)
        code (package/version-source selected hash-value)]
    (is (= (str "import ./common.nix {\n  version = \"1.62\";\n  hash = \"" hash-value "\";\n}\n") code))
    (is (false? (:registered? plan)))
    (is (str/includes? (:candidate plan) "xc16_1_62 = pkgs.callPackage ./xc16/1.62.nix"))
    (is (str/includes? (:candidate plan) "xc16 = xc16_1_61; # default stays unchanged"))
    (is (= registry (str/replace-first (:candidate plan) (:line plan) "")))
    (is (:registered? (package/registration registry (details "--family" "xc16" "--version" "1.61"))))
    (is (thrown? clojure.lang.ExceptionInfo (package/registration "pkgs: {}" selected))))
  (let [selected (details "--url" "https://example.test/xc16-v1.62-full-install-linux64-installer.run")]
    (is (str/includes? (package/version-source selected hash-value) "  url = \"https://example.test/"))))

(deftest all-registration-blocks-test
  (let [current (slurp "pkgs/default.nix")]
    (doseq [family ["xc8" "xc16" "xc32" "xc-dsc"]]
      (let [selected (details "--family" family "--version" "99.99")
            plan (package/registration current selected)]
        (is (false? (:registered? plan)))
        (is (str/includes? (:line plan) (str family "_99_99 = pkgs.callPackage ./" family "/99.99.nix")))
        (is (= current (str/replace-first (:candidate plan) (:line plan) "")))))))

(deftest dangling-version-link-test
  (let [target (str *root* "/pkgs/xc16/1.62.nix")]
    (fs/create-sym-link target "missing.nix")
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"refusing to overwrite"
                         (package/write-check! *root* (details "--family" "xc16" "--version" "1.62") registry)))
    (is (fs/exists? target {:nofollow-links true}))))

(deftest hash-probe-test
  (let [seen (atom nil) selected (details "--family" "xc16" "--version" "1.62")]
    (with-redefs [project/nix-result
                  (fn [& args] (reset! seen args) {:exit 1 :err (str "got: " hash-value)})]
      (is (= hash-value (package/installer-hash *root* selected)))
      (is (str/ends-with? (last @seen) "in compiler.src"))
      (is (str/includes? (last @seen) "git+file://")))
    (doseq [result [{:exit 0 :err (str "got: " hash-value)}
                    {:exit 1 :err "download failed"}]]
      (with-redefs [project/nix-result (fn [& _] result)]
        (is (thrown? clojure.lang.ExceptionInfo (package/installer-hash *root* selected)))))))

(deftest dry-run-does-not-write-test
  (with-redefs [package/installer-hash (fn [& _] hash-value)
                package/verify! (fn [& _] (throw (ex-info "Unexpected verification" {})))]
    (let [output (with-out-str (package/scaffold! *root* (details "--family" "xc16" "--version" "1.62")))]
      (is (str/includes? output "Dry run:"))
      (is (str/includes? output "No package files changed"))
      (is (= registry (slurp (str *root* "/pkgs/default.nix"))))
      (is (not (fs/exists? (str *root* "/pkgs/xc16/1.62.nix")))))))

(deftest write-and-refuse-overwrite-test
  (with-redefs [package/installer-hash (fn [& _] hash-value)]
    (let [selected (details "--family" "xc16" "--version" "1.62" "--write")]
      (with-out-str (package/scaffold! *root* selected))
      (is (str/includes? (slurp (str *root* "/pkgs/default.nix")) "xc16_1_62 ="))
      (is (= (package/version-source selected hash-value) (slurp (str *root* "/pkgs/xc16/1.62.nix"))))
      (with-redefs [package/installer-hash (fn [& _] (throw (ex-info "Unexpected download" {})))]
        (is (thrown-with-msg? clojure.lang.ExceptionInfo #"refusing to overwrite"
                             (package/scaffold! *root* selected)))))))

(deftest failed-verification-does-not-write-test
  (with-redefs [package/installer-hash (fn [& _] hash-value)
                package/verify! (fn [& _] (throw (ex-info "Verification failed" {})))]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Verification failed"
                         (with-out-str (package/scaffold! *root* (details "--family" "xc16" "--version" "1.62"
                                                                        "--write" "--verify")))))
    (is (= registry (slurp (str *root* "/pkgs/default.nix"))))
    (is (not (fs/exists? (str *root* "/pkgs/xc16/1.62.nix"))))))

(deftest preserve-concurrent-edits-test
  (with-redefs [package/installer-hash
                (fn [& _] (spit (str *root* "/pkgs/default.nix") (str registry "# human edit\n")) hash-value)]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"changed"
                         (with-out-str (package/scaffold! *root* (details "--family" "xc16" "--version" "1.62" "--write")))))
    (is (str/ends-with? (slurp (str *root* "/pkgs/default.nix")) "# human edit\n"))
    (is (not (fs/exists? (str *root* "/pkgs/xc16/1.62.nix"))))))

(deftest locked-registry-test
  (spit (str *root* "/pkgs/.#default.nix") "editor lock")
  (is (thrown-with-msg? clojure.lang.ExceptionInfo #"locked"
                       (package/write-check! *root* (details "--family" "xc16" "--version" "1.62") registry))))

(deftest failed-registry-replacement-test
  (let [selected (details "--family" "xc16" "--version" "1.62")
        plan (package/registration registry selected)
        content (package/version-source selected hash-value)]
    (with-redefs [fs/move (fn [& _] (throw (ex-info "Move failed" {})))]
      (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Move failed"
                           (package/write-files! *root* selected registry (:candidate plan) content)))
      (is (= registry (slurp (str *root* "/pkgs/default.nix"))))
      (is (not (fs/exists? (str *root* "/pkgs/xc16/1.62.nix")))))))

(deftest temporary-verification-cleanup-test
  (doseq [status [0 1]]
    (let [directory (atom nil)]
      (with-redefs [process/shell
                    (fn [_ & args]
                      (let [candidate (second (drop-while #(not= "candidate" %) args))]
                        (reset! directory (fs/parent candidate))
                        (is (fs/exists? (str @directory "/common.nix")))
                        {:exit status :out "/nix/store/verification-result\n"}))]
        (if (zero? status)
          (package/verify! *root* (details "--family" "xc16" "--version" "1.62") "candidate")
          (is (thrown? clojure.lang.ExceptionInfo
                       (package/verify! *root* (details "--family" "xc16" "--version" "1.62") "candidate"))))
        (is (not (fs/exists? @directory)))))))
