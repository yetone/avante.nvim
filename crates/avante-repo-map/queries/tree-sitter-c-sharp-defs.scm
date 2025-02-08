(class_declaration
  name: (identifier) @class
  (parameter_list)? @method)  ;; Primary constructor

(record_declaration
  name: (identifier) @class
  (parameter_list)? @method)  ;; Primary constructor

(interface_declaration
  name: (identifier) @class)

(method_declaration) @method

(constructor_declaration) @method

(property_declaration) @class_variable

(field_declaration
  (variable_declaration
    (variable_declarator))) @class_variable

(enum_declaration
  body: (enum_member_declaration_list
    (enum_member_declaration) @enum_item))
