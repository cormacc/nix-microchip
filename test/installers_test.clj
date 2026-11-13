(ns installers-test
  (:require [clojure.test :refer [deftest is]]
            [installers :as installers]))

(def inventory
  {"xc16_1_61" {:name "xc16-v1.61.run" :path "/nix/store/a-xc16-v1.61.run"}
   "xc16" {:name "xc16-v1.61.run" :path "/nix/store/a-xc16-v1.61.run"}
   "xc8_4_00" {:name "xc8-v4.00.run" :path "/nix/store/b-xc8-v4.00.run"}
   "xc32_6_00" {:name "xc32-v6.00.run" :path "/nix/store/c-xc32-v6.00.run"}})

(deftest save-copies-each-stored-uncached-installer-once
  (let [in-store? #{"/nix/store/a-xc16-v1.61.run" "/nix/store/b-xc8-v4.00.run"}]
    (is (= [{:action :copy :name "xc16-v1.61.run" :path "/nix/store/a-xc16-v1.61.run"}]
           (vec (installers/plan :save inventory in-store? #{"xc8-v4.00.run"}))))))

(deftest import-adds-cached-installers-missing-from-the-store
  (let [in-store? #{"/nix/store/b-xc8-v4.00.run"}
        cached #{"xc16-v1.61.run" "xc8-v4.00.run" "notes.txt"}]
    (is (= [{:action :add :name "xc16-v1.61.run" :path "/nix/store/a-xc16-v1.61.run"}
            {:action :unknown :name "notes.txt"}]
           (vec (installers/plan :import inventory in-store? cached))))))

(deftest status-lists-each-attribute
  (is (= [["xc16" "store" "cached" "xc16-v1.61.run"]
          ["xc16_1_61" "store" "cached" "xc16-v1.61.run"]
          ["xc32_6_00" "-" "-" "xc32-v6.00.run"]
          ["xc8_4_00" "-" "-" "xc8-v4.00.run"]]
         (vec (installers/status-rows inventory #{"/nix/store/a-xc16-v1.61.run"}
                                      #{"xc16-v1.61.run"})))))

(deftest arguments
  (is (= :status (installers/parse-args [])))
  (is (= :import (installers/parse-args ["import"])))
  (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Usage"
                        (installers/parse-args ["load"]))))
