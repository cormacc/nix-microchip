(ns packs
  (:require [babashka.process :as process]
            [clojure.data.xml :as xml]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(def online-index "https://packs.download.microchip.com/index.idx")

(defn nix-result [& args]
  (apply process/shell {:out :string :err :string :continue true} "nix" args))

(defn bundled-index []
  (let [{:keys [exit out err]} (nix-result "build" "--no-link" "--print-out-paths" ".#mplab-x-unwrapped")]
    (if (zero? exit)
      (str (str/trim out) "/share/mplab-x/packs/index.idx")
      (throw (ex-info "Cannot build mplab-x-unwrapped." {:error err})))))

(defn pdsc-elements [source]
  (with-open [reader (io/reader source)]
    (let [document (xml/parse reader :namespace-aware false :location-info false)]
      (doall (filter #(= :pdsc (:tag %)) (tree-seq map? :content document))))))

(defn pack-name [{:keys [attrs]}]
  (let [filename (or (:name.gz attrs) (:name attrs))
        [vendor name] (str/split (str/replace filename #"\.pdsc(?:\.gz)?$" "") #"\." 2)]
    {:vendor vendor :name name :version (:version attrs)
     :kind (if (contains? attrs :tool-name) "tool" "device")}))

(defn parse-args [args]
  (loop [args args online? false filter-text nil]
    (if-let [arg (first args)]
      (cond
        (= arg "--online") (recur (rest args) true filter-text)
        (str/starts-with? arg "--") (throw (ex-info (str "Unknown option: " arg) {}))
        filter-text (throw (ex-info "packs accepts one optional filter." {}))
        :else (recur (rest args) online? arg))
      {:online? online? :filter-text filter-text})))

(defn main [& args]
  (try
    (let [{:keys [online? filter-text]} (parse-args args)
          source (if online? online-index (bundled-index))]
      (doseq [{:keys [kind vendor name version]}
              (sort-by (juxt :vendor :name :version) (map pack-name (pdsc-elements source)))
              :when (or (nil? filter-text) (str/includes? name filter-text))]
        (println kind (str vendor "/" name) version)))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [stderr (:error (ex-data error))]
          (println stderr)))
      (System/exit 1))))
