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
import plinth/browser/clipboard
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
  UserClickedCopy
}

fn update(model: Model, msg: Msg) -> Model {
  let output =
    parse(model)
    |> result.map_error(ParseError)
    |> result.try(generate)
    |> result.map(string.replace(_,"\t","  "))
    |> result.map_error(string.inspect)
    |> result.unwrap_both
  case msg {
    ChangeText(value) -> value
    UserClickedCopy -> {
      clipboard.write_text(output)
      model
    }
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

fn textarea_styles() {
  [
    s.property("tab-size", "2"),
    s.background("#111111"),
    s.border("none"),
    s.property("resize", "none"),
    s.padding_("10px"),
    s.margin_("0"),
  ]
}

fn input_class() {
  textarea_styles()
  |> list.append([
    s.color("whitesmoke"),
    s.background("#202020"),
    s.focus_visible([s.outline("none"), s.background("#222222")]),
    s.flex_grow("1"),
  ])
  |> scl
}

fn template_class() {
  textarea_styles()
  |> list.append([
    s.color("rgb(151, 151, 151)"),
    s.background("#151515"),
    s.focus_visible([s.outline("none"), s.background("#171717")]),
    s.flex_grow("0"),
    s.property("flex-shrink", "1"),
  ])
  |> scl
}

fn output_class() {
  textarea_styles()
  |> list.append([s.color("#77ff99"), s.flex_grow("2")])
  |> scl
}

fn text_holder_class() {
  [
    s.width_("90%"),
    s.height_("100%"),
    s.background("#000"),
    s.margin_("auto"),
    s.display("flex"),
    s.flex_direction("row"),
  ]
  |> scl
}

fn view(model: Model) -> element.Element(Msg) {
  let output =
    parse(model)
    |> result.map_error(ParseError)
    |> result.try(generate)
    |> result.map_error(string.inspect)
    |> result.unwrap_both
  html.div(
    [
      scl([
        s.display("flex"),
        s.flex_direction("column"),
        s.height_("100%"),
        s.font_family("monospace"),
      ]),
    ],
    [
      html.h1(
        [
          scl([
            s.text_align("center"),
            s.font_size_("2rem"),
            s.color("#44ff66"),
            s.margin_("0.5rem 0"),
          ]),
        ],
        [html.text("🤖 The Gloder")],
      ),
      html.div([text_holder_class()], [
        html.div(
          [
            scl([
              s.flex_grow("1"),
              s.display("flex"),
              s.flex_direction("column"),
              s.gap_("0"),
            ]),
          ],
          [
            html.textarea(
              [
                attribute.attribute("spellcheck", "false"),
                template_class(),
                attribute.disabled(True),
                attribute.rows(1),
              ],
              "type YourData {",
            ),
            html.textarea(
              [
                event.on_input(ChangeText),
                input_class(),
                attribute.attribute("spellcheck", "false"),
              ],
              model,
            ),
            html.textarea(
              [
                attribute.attribute("spellcheck", "false"),
                template_class(),
                attribute.disabled(True),
                attribute.rows(1),
              ],
              "}",
            ),
          ],
        ),
        html.div([scl([s.flex_grow("2"),s.display("flex"), s.flex_direction("column")])], [
          html.textarea([output_class(), attribute.disabled(True)], output),
          html.button([event.on_click(UserClickedCopy), scl([s.position("absolute"),
          s.bottom_("5vh"),
          s.right_("10vw"),
          s.font_size_("1.2rem"),
          s.padding_("0.6rem 0.8rem"),
          s.border_radius_("0"),
          s.border("none"),
          s.font_weight("600"),
          s.background("#bbb"),
          s.color("#111"),
          s.hover([s.cursor("pointer"), s.background("#eee")])
          ])],[html.text("📋 Copy")]),
        ]),
      ]),
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
