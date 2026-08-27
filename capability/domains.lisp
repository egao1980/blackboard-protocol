(in-package #:capability-protocol)

;;; Abstract domains — GF names only. Adapters / tests supply methods.
;;; Provider types live in adapter repos (llm-protocol, …), not here.

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
  (:operation complete ((prompt t)) :returns t :doc "Complete PROMPT.")
  (:operation stream-complete ((prompt t)) :returns t
   :doc "Streaming sibling of COMPLETE."))

(defcapability :llm-tools "Tool descriptors on generate (not executors).")

(defcapability :llm-vision "Image parts on LLM turns.")

(defcapability :llm-audio "Audio input parts on LLM turns.")

(defcapability :llm-video "Video parts on LLM turns.")

(defcapability :llm-files "Document / file parts on LLM turns."
  (:operation upload-file ((data t)) :returns t
   :doc "Upload DATA; return a provider file-id string."))

(defcapability :llm-speech "Speech synthesis (audio out)."
  (:operation synthesize ((text t)) :returns t :doc "TEXT → audio."))

(defcapability :llm-transcription "Speech recognition (audio in → text)."
  (:operation transcribe ((audio t)) :returns t :doc "AUDIO → text."))

(defcapability :llm-thinking "Reasoning / thinking parts.")

(defcapability :llm-structured-output "JSON schema / constrained decode.")

(defcapability :llm-responses "Responses-style respond (items, not chat turns).")

(defcatalogue :world
    "Board world I/O. Presence on a host = that domain is available."
  :compute :code-editing :version-control :web-search :communication)

(defcatalogue :llm
    "LLM generation and modalities. Adapter registers the subset the backend implements."
  :llm-generation :llm-tools :llm-vision :llm-audio :llm-video :llm-files
  :llm-speech :llm-transcription :llm-thinking :llm-structured-output
  :llm-responses)
