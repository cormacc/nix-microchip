#!/usr/bin/env bb
(require '[babashka.fs :as fs]
         '[clojure.java.io :as io]
         '[clojure.set :as set]
         '[clojure.string :as str])

(def conservative-files
  #{"mplab_platform/bin/extractobjectdependencies.jar"
    "mplab_platform/bin/fixDeps"
    "mplab_platform/dat/en_msgs.txt"})

(def access-pattern
  #"(?:openat\([^,]+, |(?:open|execve)\()\"([^\"]+)\"")

(defn fail! [message]
  (binding [*out* *err*]
    (println message))
  (System/exit 1))

(defn trace-paths [trace-root trace]
  (with-open [reader (io/reader trace)]
    (->> (line-seq reader)
         (keep (fn [line]
                 (when (and (not (str/includes? line "= -1"))
                            (re-find #"(?:openat|open|execve)\(" line))
                   (second (re-find access-pattern line)))))
         (filter #(str/includes? % trace-root))
         (map #(subs % (+ (str/index-of % trace-root) (count trace-root))))
         (map #(str (fs/normalize %)))
         (remove #(or (str/starts-with? % "/")
                      (str/starts-with? % "../")))
         set)))

(let [[source-root trace-root generator-trace & build-traces] *command-line-args*]
  (when-not (and source-root trace-root generator-trace (seq build-traces))
    (fail! "Usage: regenerate-headless-files.clj <source-root> <trace-root> <generator-trace> <build-trace>..."))
  (let [source-root (str (fs/absolutize source-root))
        trace-root (str (str/replace trace-root #"/$" "") "/")]
    (when-not (fs/directory? source-root)
      (fail! (str "Source root is not a directory: " source-root)))
    (let [traces (cons generator-trace build-traces)
          traced-files (apply set/union (map #(trace-paths trace-root %) traces))
          files (->> (set/union traced-files conservative-files)
                     (filter #(fs/regular-file? (str (fs/path source-root %))))
                     sort)]
      (println (str/join "\n" files)))))
