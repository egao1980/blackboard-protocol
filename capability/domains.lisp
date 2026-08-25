(in-package #:capability-protocol)

;;; Abstract domains — GF names only. Adapters / tests supply methods.
;;; :llm-generation is a name reserved for adapters; core has no provider.

(defcapability :compute "Run commands / evaluate."
  (:operation run-command ((argv t)) :returns t
   :doc "Run ARGV; return a result plist."))

(defcapability :code-editing "Read and write files."
  (:operation read-file ((path t)) :returns t :doc "Read PATH.")
  (:operation write-file ((path t) (content t)) :returns t :doc "Write PATH."))

(defcapability :version-control "VCS operations."
  (:operation git-status () :returns t :doc "Working-tree status."))

(defcapability :web-search "Search the web."
  (:operation web-search ((query t)) :returns t :doc "Search QUERY."))

(defcapability :communication "Outbound messages."
  (:operation send-message ((to t) (body t)) :returns t :doc "Send BODY to TO."))

(defcapability :llm-generation "LLM completion (adapter implements)."
  (:operation complete ((prompt t)) :returns t :doc "Complete PROMPT."))
