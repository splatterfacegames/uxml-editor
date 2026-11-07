class_name EdError
extends RefCounted
## A refused editor operation. Commands return an EdError instead of a
## transaction when an edit cannot be expressed exactly. A refusal never
## changes a source buffer or the history.

var code: String = ""
var message: String = ""
var detail: Variant = null


func _init(error_code: String = "", error_message: String = "", error_detail: Variant = null) -> void:
	code = error_code
	message = error_message
	detail = error_detail


static func make(error_code: String, error_message: String, error_detail: Variant = null) -> EdError:
	return EdError.new(error_code, error_message, error_detail)


func _to_string() -> String:
	return "%s: %s" % [code, message]
