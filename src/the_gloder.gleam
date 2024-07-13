import glance
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/event
import mat
import sketch as s
import sketch/lustre as sketch_lustre
import sketch/options as sketch_options

type GloderError {
  GenerateError(String)
  ParseError(glance.Error)
}

pub type Model =
  String

fn scl(styles) {
  styles |> s.class |> s.to_lustre
}

fn init(_flags) {
  "User(name: String, age: Int)"
}

pub type Msg {
  ChangeText(String)
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    ChangeText(value) -> value
  }
}

fn add_template(input) {
  "type Data {" <> input <> "}"
}

fn parse(input: String) -> Result(glance.Module, glance.Error) {
  glance.module(add_template(input))
}

fn generate(input: glance.Module) -> Result(String, GloderError) {
  use custom_type <- result.try(
    list.first(input.custom_types)
    |> result.replace_error(GenerateError("No custom types?")),
  )
  list.try_map(custom_type.definition.variants, fn(variant) {
    use decoder <- result.map(generate_decoder(variant))
    let signature = generate_function_signature(variant)
    mat.format2(
      "{} {\n\t{}\n\t|> json.decode(from: json_string, using: _)\n}",
      signature,
      decoder,
    )
  })
  |> result.map(string.join(_, "\n\n"))
}

fn generate_function_signature(variant: glance.Variant) -> String {
  mat.format2(
    "pub fn {}_from_json(json_string: String) -> Result({}, json.DecodeError)",
    variant.name |> string.lowercase,
    variant.name,
  )
}

fn generate_decoder(variant: glance.Variant) -> Result(String, GloderError) {
  let field_count = list.length(variant.fields)
  use field_decoders <- result.map(list.try_map(
    variant.fields,
    generate_field_decode,
  ))
  mat.format3(
    "dynamic.decode{}(\n\t\t{},\n\t\t{}\n\t)",
    field_count,
    variant.name,
    field_decoders |> string.join(",\n\t\t"),
  )
}

fn type_to_dynamic(type_: glance.Type) -> Result(String, GloderError) {
  case type_ {
    glance.NamedType(name, parameters: parameters, ..) ->
      case name {
        "String" -> Ok("dynamic.string")
        "Int" -> Ok("dynamic.int")
        "Bool" -> Ok("dynamic.bool")
        "Float" -> Ok("dynamic.float")
        "List" ->
          list.first(parameters)
          |> result.replace_error(GenerateError("List requires a subtype"))
          |> result.try(type_to_dynamic)
          |> result.map(fn(type_) { mat.format1("dynamic.list({})", type_) })
        "Option" ->
          list.first(parameters)
          |> result.replace_error(GenerateError("Option requires a subtype"))
          |> result.try(type_to_dynamic)
          |> result.map(fn(type_) { mat.format1("dynamic.optional({})", type_) })
        n -> Ok(string.lowercase(n) <> "_from_json")
      }
    glance.TupleType(types) ->
      case list.try_map(types, type_to_dynamic) {
        Error(e) -> Error(e)
        Ok(types) ->
          Ok(mat.format2(
            "dynamic.decode{}({})",
            list.length(types),
            types |> string.join(", "),
          ))
      }
    glance.VariableType(..) ->
      Error(GenerateError("Variable types are not supported"))
    glance.FunctionType(..) ->
      Error(GenerateError("Function types are not supported"))
    glance.HoleType(..) -> Error(GenerateError("Hole types are not supported"))
  }
}

fn generate_field_decode(
  field: glance.Field(glance.Type),
) -> Result(String, GloderError) {
  let res = case field.item {
    glance.NamedType("Option", parameters: parameters, ..) ->
      list.first(parameters)
      |> result.replace_error(GenerateError("Option requires a subtype"))
      |> result.try(type_to_dynamic)
      |> result.map(fn(type_) { #("dynamic.optional_field", type_) })
    _ ->
      type_to_dynamic(field.item)
      |> result.map(fn(type_) { #("dynamic.field", type_) })
  }
  use #(field_function, type_decoder) <- result.try(res)
  field.label
  |> option.to_result(GenerateError("Field needs a label"))
  |> result.map(string.replace(_, "_", "-"))
  |> result.map(fn(label) {
    mat.format3("{}(\"{}\", {})", field_function, label, type_decoder)
  })
}

fn view(model: Model) -> element.Element(Msg) {
  html.div(
    [scl([s.width_("100vw"), s.height_("100vh"), s.background("#222222")])],
    [
      html.textarea(
        [
          event.on_input(ChangeText),
          scl([
            s.width_("30vw"),
            s.height_("30vh"),
            s.property("tab-size", "4"),
            s.background("#222222"),
            s.color("#eee"),
          ]),
          attribute.attribute("spellcheck", "false"),
        ],
        model,
      ),
      html.textarea(
        [
          scl([
            s.width_("60vw"),
            s.height_("30vh"),
            s.property("tab-size", "4"),
            s.background("#222"),
            s.color("#eee"),
          ]),
          attribute.disabled(True),
        ],
        parse(model)
          |> result.map_error(ParseError)
          |> result.try(generate)
          |> result.map_error(string.inspect)
          |> result.unwrap_both,
      ),
    ],
  )
}

pub fn main() {
  let assert Ok(cache) =
    sketch_options.document()
    |> sketch_lustre.setup()

  let app =
    view
    |> sketch_lustre.compose(cache)
    |> lustre.simple(init, update, _)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}
