(property_declaration) @variable

(function_declaration) @function


(class_declaration
	_?
	[
	 "struct"
	 "class"
	]) @class

(class_declaration
	_?
	 "enum"
	) @enum

(class_body
    (property_declaration) @class_variable)

(class_body
    (function_declaration) @method)

(class_body
    (init_declaration) @method)

(protocol_declaration
    body: (protocol_body
        (protocol_function_declaration) @function))

(protocol_declaration
    body: (protocol_body
        (protocol_property_declaration) @class_variable))

(class_declaration
	body: (enum_class_body
            (enum_entry) @enum_item))
