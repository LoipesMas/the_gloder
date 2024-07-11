import glance
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lustre
import lustre/element
import lustre/element/html
import lustre/event
import mat
import sketch as s
import sketch/lustre as sketch_lustre
import sketch/options as sketch_options

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

fn generate(input: glance.Module) {
  use custom_type <- result.try(list.first(input.custom_types))
  list.map(custom_type.definition.variants, fn(variant) {
    let signature = generate_function_signature(variant)
    mat.format2(
      "{} {\n\t{}\n}",
      signature,
      generate_decoder(variant),
    )
  })
  |> string.join("\n\n")
  |> Ok
}

fn generate_function_signature(variant: glance.Variant) -> String {
  mat.format2(
    "pub fn {}_from_json(json_string: String) -> Result({}, json.DecodeError)",
    variant.name |> string.lowercase,
    variant.name,
  )
}

fn generate_decoder(variant: glance.Variant) -> String {
  let field_count = list.length(variant.fields)
  let field_decoders = list.map(variant.fields, generate_field_decode)
  mat.format3(
    "dynamic.decode{}(\n\t\t{},\n\t\t{}\n\t)",
    field_count,
    variant.name,
    field_decoders |> string.join(",\n\t\t"),
  )
}

fn type_to_dynamic(type_: glance.Type) -> String {
  case type_ {
    glance.NamedType(name, ..) ->
      case name {
        "String" -> "decode.string"
        "Int" -> "decode.int"
        n -> string.lowercase(n) <> "_from_json"
      }
    glance.TupleType(types) ->
      mat.format2(
        "decode.decode{}({})",
        list.length(types),
        list.map(types, type_to_dynamic) |> string.join(","),
      )
    type_ -> todo as string.inspect(type_)
  }
}

fn generate_field_decode(field: glance.Field(glance.Type)) -> String {
  mat.format2(
    "decode.field(\"{}\",{})",
    field.label |> option.unwrap("<UNKNOWN>"),
    type_to_dynamic(field.item),
  )
}

fn view(model: Model) -> element.Element(Msg) {
  html.div([scl([s.margin_("2rem")])], [
    html.textarea(
      [event.on_input(ChangeText), scl([s.width_("30vw"), s.height_("30vh")])],
      model,
    ),
    html.textarea(
      [scl([s.width_("60vw"), s.height_("30vh")])],
      parse(model)
        |> result.map(generate)
        |> result.map(result.unwrap(_, or: ""))
        |> result.map_error(string.inspect)
        |> result.unwrap_both,
    ),
  ])
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
