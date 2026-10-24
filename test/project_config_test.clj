(ns project-config-test
  (:require [clojure.test :refer [deftest is testing]]
            [project-config :as project]))

(deftest directory-and-file-input-test
  (let [directory "examples/mplab/firmware.X"
        file (str directory "/nbproject/configurations.xml")
        configurations (project/project-configurations directory)]
    (is (= configurations (project/project-configurations file)))
    (is (= ["default"] (mapv #(get-in % [:attrs :name]) configurations)))
    (is (= "XC16" (project/element-text (first configurations) :languageToolchain)))
    (is (= [{:vendor "Microchip" :name "dsPIC33E-GM-GP-MC-GU-MU_DFP"
             :version "1.7.401"}]
           (vec (project/configuration-packs (first configurations)))))))

(deftest missing-project-test
  (is (thrown-with-msg? clojure.lang.ExceptionInfo #"not found"
                       (project/project-configurations "test/missing-project"))))

(deftest exact-compiler-test
  (with-redefs [project/packaged-attributes
                (fn [family] (case family
                               "xc16" ["xc16_1_61" "xc16_2_10"]
                               "xc-dsc" ["xc-dsc_4_00"]))]
    (is (= "xc16_1_61" (project/compiler-attribute "XC16" "1.61")))
    (is (= "xc-dsc_4_00" (project/compiler-attribute "XC-DSC" "4.00")))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"not packaged"
                         (project/compiler-attribute "XC16" "9.99")))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Unsupported"
                         (project/compiler-attribute "unknown" "1.0")))))

(deftest pack-hash-status-test
  (let [hash "sha256-NSLRbSv/UQcvVhFLhqc+eQixQupAA5aFuCwdoHyVEyc="
        pack {:vendor "Microchip" :name "Example_DFP" :version "1.0.0"}]
    (testing "a hash mismatch is the expected failed build"
      (with-redefs [project/nix-result (fn [& _] {:exit 1 :err (str "got: " hash)})]
        (is (= hash (project/pack-hash "/example" pack)))))
    (testing "success or another failure is not a hash result"
      (doseq [result [{:exit 0 :err (str "got: " hash)}
                      {:exit 1 :err "network failed"}
                      {:exit 1 :err "got: sha256-invalid"}]]
        (with-redefs [project/nix-result (fn [& _] result)]
          (is (thrown? clojure.lang.ExceptionInfo
                       (project/pack-hash "/example" pack))))))))

(deftest nix-string-test
  (is (= "\"plain\"" (project/nix-string "plain")))
  (is (= "\"\\${notNix}\"" (project/nix-string "${notNix}")))
  (is (= "\"a\\\"b\\\\c\"" (project/nix-string "a\"b\\c"))))
