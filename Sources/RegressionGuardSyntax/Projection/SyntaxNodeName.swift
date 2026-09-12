import SwiftSyntax

/// The name a projected node carries, when it declares or references one.
///
/// Split out from the projection because the rule families read `name` for different reasons and
/// each case here is a decision one of them depends on, not a formatting nicety.
enum SyntaxNodeName {
  /// - Returns: the name this node declares or references, or `nil` when it carries none.
  static func of(_ syntax: Syntax) -> String? {
    // Covers every `name`-bearing nominal declaration - class, struct, enum, actor, protocol,
    // typealias - in one case, so only the declarations spelling their name differently follow.
    if let named = syntax.asProtocol(NamedDeclSyntax.self) { return named.name.text }
    return declarationName(syntax) ?? expressionName(syntax)
  }

  private static func declarationName(_ syntax: Syntax) -> String? {
    switch syntax.as(SyntaxEnum.self) {
    case .functionDecl(let decl):
      return decl.name.text
    case .initializerDecl:
      return "init"
    case .extensionDecl(let decl):
      return decl.extendedType.trimmedDescription
    case .importDecl(let decl):
      return decl.path.trimmedDescription
    case .variableDecl(let decl):
      return decl.bindings.first?.pattern.trimmedDescription
    case .identifierPattern(let pattern):
      return pattern.identifier.text
    // The `#` is part of how a macro is written, so a rule matching `#expect` matches what the
    // author typed rather than a name the projection invented.
    case .macroExpansionDecl(let decl):
      return "#" + decl.macroName.text
    default:
      return nil
    }
  }

  private static func expressionName(_ syntax: Syntax) -> String? {
    switch syntax.as(SyntaxEnum.self) {
    case .declReferenceExpr(let expr):
      return expr.baseName.text
    // A call's callee, so a rule asking what was called does not have to walk into the child that
    // happens to hold the name.
    case .memberAccessExpr(let expr):
      return expr.declName.baseName.text
    case .attribute(let attribute):
      return attribute.attributeName.trimmedDescription
    // `try`, `try?` and `try!` share one kind, so the spelling is the only thing separating
    // propagating an error from discarding it.
    case .tryExpr(let expr):
      return "try" + (expr.questionOrExclamationMark?.text ?? "")
    case .macroExpansionExpr(let expr):
      return "#" + expr.macroName.text
    case .booleanLiteralExpr(let expr):
      return expr.literal.text
    case .integerLiteralExpr(let expr):
      return expr.literal.text
    case .floatLiteralExpr(let expr):
      return expr.literal.text
    default:
      return nil
    }
  }
}
