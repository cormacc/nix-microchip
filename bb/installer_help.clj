(ns installer-help
  (:require [babashka.process :as process]
            [clojure.string :as str]))

(defn nix-result [& args]
  (apply process/shell {:out :string :err :string :continue true} "nix" args))

(defn main [& args]
  (try
    (when (seq args)
      (throw (ex-info "Usage: bb installer-help" {})))
    (let [{:keys [exit out err]} (nix-result "build" "--no-link" "--print-out-paths" ".#mplab-x-unwrapped.installerHelp")]
      (if (zero? exit)
        (let [output (str/trim out)]
          (print (slurp (str output "/version.txt")))
          (print (slurp (str output "/help.txt"))))
        (throw (ex-info "Cannot build installer help." {:error err}))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [stderr (:error (ex-data error))]
          (println stderr)))
      (System/exit 1))))
