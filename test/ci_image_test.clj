(ns ci-image-test
  (:require [babashka.fs :as fs]
            [babashka.process :as process]
            [cheshire.core :as json]
            [ci-image :as image]
            [clojure.string :as str]
            [clojure.test :refer [deftest is use-fixtures]]
            [project-config :as project]))

(def ^:dynamic *scratch* nil)

(use-fixtures :each
  (fn [run-test]
    (fs/create-dirs ".tmp")
    (binding [*scratch* (str (fs/create-temp-dir {:dir ".tmp" :prefix "ci-image-test-"}))]
      (try (run-test) (finally (fs/delete-tree *scratch*))))))

(defn configuration [name compiler version packs]
  {:tag :conf :attrs {:name name}
   :content [{:tag :toolsSet
              :content [{:tag :languageToolchain :content [compiler]}
                        {:tag :languageToolchainVersion :content [version]}]}
             {:tag :packs :content (mapv #(hash-map :tag :pack :attrs %) packs)}]})

(deftest parse-args-test
  (is (= {:help? true} (image/parse-args ["--help"])))
  (is (= ["xc16_1_61" "xc-dsc_4_00"]
         (:compilers (image/parse-args ["--compiler" "xc16_1_61"
                                        "--compiler" "xc-dsc_4_00"]))))
  (is (= "firmware-ci" (:name (image/parse-args ["--project" "fixture.X" "--name" "firmware-ci"]))))
  (doseq [name ["xc-cli" "ghcr.io/owner/ci" "localhost:5000/team/ci" "team/build__tools"]]
    (is (= name (:name (image/parse-args ["--project" "fixture.X" "--name" name]))))))

(deftest rejected-options-test
  (doseq [args [[] ["--bad"] ["--project" "fixture.X" "--bad"]
                ["--compiler"] ["--project" "--name" "image"]
                ["--compiler" "xc16_1_61" "--pack"]
                ["--project" "fixture.X" "--compiler" "xc16_1_61"]
                ["--project" "fixture.X" "--pack" "Microchip/DFP/1.0"]
                ["--compiler" "xc16_1_61" "--configuration" "default"]
                ["--project" "a" "--project" "b"]
                ["--project" "a" "--name" "x" "--name" "y"]
                ["--project" "a" "--configuration" "x" "--configuration" "y"]
                ["--project" "fixture.X" "--name" "Uppercase"]
                ["--project" "fixture.X" "--name" "ci:latest"]
                ["--project" "fixture.X" "--name" "ci@sha256:abc"]
                ["--project" "fixture.X" "--name" "ci//bad"]]]
    (is (thrown? clojure.lang.ExceptionInfo (image/parse-args args)) (pr-str args))))

(deftest configuration-choice-test
  (let [a (configuration "default" "XC16" "1.61" [])
        b (configuration "release" "XC8" "3.10" [])]
    (is (= a (image/select-configuration [a] nil)))
    (is (= b (image/select-configuration [a b] "release")))
    (doseq [[confs requested] [[[] nil] [[a b] nil] [[a] "missing"]
                               [[a a] "default"] [[(assoc a :attrs {})] nil]]]
      (is (thrown? clojure.lang.ExceptionInfo
                   (image/select-configuration confs requested))))))

(deftest project-and-explicit-selection-test
  (let [pack {:vendor "Microchip" :name "dsPIC33E-GM-GP-MC-GU-MU_DFP"
              :version "1.7.401"}
        calls (atom [])]
    (with-redefs [project/packaged-attributes (fn [_] ["xc16_1_61"])
                  project/pack-hash (fn [_ selected] (swap! calls conj selected) "hash")]
      (let [directory (image/selection "/repo" (image/parse-args ["--project" "examples/mplab/firmware.X"]))
            file (image/selection "/repo" (image/parse-args ["--project" "examples/mplab/firmware.X/nbproject/configurations.xml"
                                                            "--configuration" "default"]))
            explicit (image/selection "/repo" (image/parse-args ["--compiler" "xc16_1_61"
                                                                "--compiler" "xc16_1_61"
                                                                "--pack" "Microchip/dsPIC33E-GM-GP-MC-GU-MU_DFP/1.7.401"
                                                                "--pack" "Microchip/dsPIC33E-GM-GP-MC-GU-MU_DFP/1.7.401"]))]
        (is (= directory file explicit))
        (is (= {:name "xc-cli" :compilers ["xc16_1_61"]
                :packs [(assoc pack :hash "hash")]} directory))
        (is (= [pack pack pack] @calls))))))

(deftest selected-configuration-only-test
  (let [pack {:vendor "Microchip" :name "Example_DFP" :version "1.0.0"}]
    (with-redefs [project/project-configurations
                  (fn [_] [(configuration "a" "XC16" "1.61" [])
                           (configuration "b" "XC8" "3.10" [pack])])
                  project/packaged-attributes (fn [family] [(str family "_3_10")])
                  project/pack-hash (fn [_ _] "hash")]
      (is (= {:name "xc-cli" :compilers ["xc8_3_10"] :packs [(assoc pack :hash "hash")]}
             (image/selection "/repo" (image/parse-args ["--project" "fixture.X" "--configuration" "b"])))))))

(deftest compiler-order-test
  (with-redefs [project/packaged-attributes (fn [_] ["xc16_1_61" "xc16_2_10"])]
    (is (= ["xc16_2_10" "xc16_1_61"]
           (:compilers (image/selection "/repo" (image/parse-args ["--compiler" "xc16_2_10"
                                                                  "--compiler" "xc16_1_61"
                                                                  "--compiler" "xc16_2_10"])))))))

(deftest missing-pack-and-compiler-test
  (with-redefs [project/packaged-attributes (fn [_] ["xc16_1_61"])
                project/pack-hash (fn [& _] (throw (ex-info "Unexpected download" {})))]
    (is (= [] (:packs (image/selection "/repo" (image/parse-args ["--compiler" "xc16_1_61"])))))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"not packaged"
                         (image/selection "/repo" (image/parse-args ["--compiler" "xc16_9_99"])))))
  (doseq [value ["xc16" "xc16_1" "unknown_1_00" "xc16_1_61;bad"]]
    (is (thrown? clojure.lang.ExceptionInfo
                 (image/selection "/repo" (image/parse-args ["--compiler" value]))))))

(deftest invalid-pack-test
  (doseq [pack [{:name "DFP" :version "1.0"}
                {:vendor "Microchip" :name "DFP" :version ""}
                {:vendor "Microchip" :name "../bad" :version "1.0"}
                {:vendor "${bad}" :name "DFP" :version "1.0"}]]
    (is (thrown? clojure.lang.ExceptionInfo (image/validate-pack pack))))
  (with-redefs [project/packaged-attributes (fn [_] ["xc16_1_61"])]
    (doseq [value ["DFP/1.0" "Microchip/DFP/" "Microchip//1.0" "a/b/c/d"]]
      (is (thrown? clojure.lang.ExceptionInfo
                   (image/selection "/repo" (image/parse-args ["--compiler" "xc16_1_61" "--pack" value])))))))

(deftest build-and-cleanup-test
  (let [selected {:name "example" :compilers ["xc16_1_61"] :packs []}
        captured (atom nil)]
    (with-redefs [process/shell
                  (fn [_ & args]
                    (let [file (second (drop-while #(not= "--file" %) args))
                          directory (str (fs/parent file))]
                      (reset! captured {:args args :directory directory
                                        :selection (json/parse-string (slurp (str directory "/selection.json")) true)
                                        :expression (slurp file)})
                      {:exit 0 :out "/nix/store/example-stream\n"}))]
      (is (= "/nix/store/example-stream" (image/build-image! *scratch* selected)))
      (is (= selected (:selection @captured)))
      (is (= ["nix" "build"] (vec (take 2 (:args @captured)))))
      (is (some #{"--no-link"} (:args @captured)))
      (is (str/includes? (:expression @captured) "git+file://"))
      (is (str/includes? (:expression @captured) "withMplabProjects = true"))
      (is (not (fs/exists? (:directory @captured)))))))

(deftest failed-build-cleanup-test
  (let [directory (atom nil)]
    (with-redefs [process/shell
                  (fn [_ & args]
                    (reset! directory (fs/parent (second (drop-while #(not= "--file" %) args))))
                    {:exit 1 :out ""})]
      (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Cannot build"
                           (image/build-image! *scratch* {:name "example" :compilers [] :packs []})))
      (is (not (fs/exists? @directory))))))
