/++
    Module just containing REPLRunner class

	Copyright: © 2019 Sobaya007
    License: use freely for any purpose
	Authors: Sobaya007

    Examples:
    --------------------
    import std;

    auto runner = new REPLRunner(); // initialize runner
    runner.addDependency("sbylib", "~master"); // add dependent library
    
    /* Read-Eval-Print Loop */
    string input;
    while (true) {
        write("> ");
        input ~= readln;
        auto result = runner.run(input);
        if (!result.success)
            writeln(result.message);
    }
    --------------------
+/
module repld.runner;

import std;
import repld.parse;
import repld.evaluator;
import dparse.ast;
import dparse.lexer;

/**
    The main class of this library.
 */
class REPLRunner {

    static struct Result {
        bool success;
        string message;
    }

    private Evaluator evaluator;
    
    /**
    Initialize execution environment
    */
    this() {
        this.evaluator = new Evaluator;
    }

    /**
    Execute the input.

    Params:
       input = input text to be evaluated

    Returns: evaluation result that contains the execution is successed and error message if failed
    */
    Result run(string input) {
        if (input.chomp == "") return success; // accept empty input

        auto parseResult = parse(input);

        try {
            if (auto decl = parseResult.peek!(VariableDeclaration)) {
                foreach (d; decl.declarators) {
                    auto type = getType(*decl);
                    auto value = d.initializer ? conv(d.initializer.tokens) : type.format!"(%s).init";
                    evaluator.evalVarDecl(type, d.name.text, value);
                }
                return success;
            }
            if (auto decl = parseResult.peek!(AutoDeclaration)) {
                foreach (p; decl.parts) {
                    evaluator.evalVarDecl("auto", p.identifier.text, conv(p.initializer.tokens));
                }
                return success;
            }
            if (auto decl = parseResult.peek!(FunctionDeclaration)) {
                if (decl.templateParameters) {
                    return fail("Template function is not allowed.");
                }
                evaluator.evalVarDecl("auto", decl.name.text, toLiteral(*decl));
                return success;
            }
            if (auto decl = parseResult.peek!(ImportDeclaration)) {
                evaluator.evalImport(conv(decl.tokens));
                return success;
            }
            if (auto st = parseResult.peek!(Statement)) {
                evaluator.evalStatement(conv(st.tokens));
                return success;
            }
            if (auto expr = parseResult.peek!(Expression)) {
                evaluator.evalExpression(conv(expr.tokens));
                return success;
            }
            if (auto msgs = parseResult.peek!(Message[])) {
                return fail((*msgs).map!(msg => msg.toString()).join("\n"));
            }
        } catch (SemanticException e) {
            return fail(e.msg);
        }
        assert(false);
    }

    /**
    Add dependency of dub registered package.

    Params:
       packageName = package name to be registered (ex. "mir-algorithm")
       versionName = version of packge (ex. "~v0.0.1")
    */
    void addDependency(string packageName, string versionName = "*") {
        evaluator.addDependency(packageName, versionName);
    }

    /**
    Get variable in an execution environment.

    Params:
       name = name of the variable

    Returns: specified variable
    */
    ref T get(T)(string name) {
        return evaluator.get!T(name);
    }

    /**
    Set variable in an execution environment.

    Params:
       name = name of the variable
       value = value to be set
    */
    void set(T)(string name, T value) {
        evaluator.set(name, value);
    }

    /**
    Alias of `set`.
    */
    void opIndexAssign(T)(T value, string name) {
        set(name, value);
    }

    private Result success() {
        return Result(true);
    }

    private Result fail(string msg) {
        return Result(false, msg);
    }
}

private string getType(VariableDeclaration decl) {
    return conv(decl.type.tokens);
}

private string toLiteral(FunctionDeclaration decl) {
    auto returnType = decl.hasAuto ? "auto" : conv(decl.returnType.tokens);
    auto attributes = (decl.hasRef ? "ref" : "")
        ~ decl.memberFunctionAttributes.map!(a => conv(a.tokens)).join(" ")
        ~ decl.attributes.map!(a => conv(a.tokens)).join(" ")
        ~ decl.storageClasses.map!(c => conv(c.tokens)).join(" ");
    auto parameters = conv(decl.parameters.tokens);
    auto functionBody = conv(decl.functionBody.tokens);

    return format!"function %s %s %s %s"(attributes, returnType, parameters, functionBody);
}

private string conv(const Token[] tokens) {
    return tokens.map!(t => t.text ? t.text : str(t.type)).join(" ");
}

unittest {
    auto runner = new REPLRunner();
    shouldSuccess(runner.run(q{ int x = 3; }));
    shouldSuccess(runner.run(q{ double y = 3.1415; }));
    shouldSuccess(runner.run(q{ int s; }));
    shouldSuccess(runner.run(q{ import std; }));
    shouldFailure(runner.run(q{ import unknownPackage; }));
    shouldSuccess(runner.run(q{ auto z = x * y; }));
    shouldSuccess(runner.run(q{ auto w = z; }));
    shouldSuccess(runner.run(q{ auto t = 3.seconds; }));
    shouldSuccess(runner.run(q{ writeln(z); }));
    shouldFailure(runner.run(q{ writeln(a); }), "Error: undefined identifier `a`");
    shouldSuccess(runner.run(q{ iota(x).map!(a => a * 2).writeln; }));
    shouldSuccess(runner.run(q{ 1+2 }));
    shouldSuccess(runner.run(q{ void po() { writeln("po"); } }));
    shouldFailure(runner.run(q{ void func(T)() { writeln(T.init); } }), "Template function is not allowed.");
    shouldSuccess(runner.run(q{ po(); }));
    shouldSuccess(runner.run(q{ auto doubleX = { return x *= 2; }; }));
    shouldSuccess(runner.run(q{ doubleX(); }));
    shouldSuccess(runner.run(q{ assert(x == 6); }));
    shouldFailure(runner.run(q{ auto a = 8 }), "Primary expression expected");
    runner.addDependency("sbylib", "~>0.0.4");
    shouldSuccess(runner.run(q{ import sbylib.math; }));
    shouldSuccess(runner.run(q{ assert(mat2(1) * vec2(2,3) == vec2(5)); }));
}

version (unittest) {
    void shouldSuccess(REPLRunner.Result result) {
        assert(result.success && result.message is null, result.message);
    }

    void shouldFailure(REPLRunner.Result result, string errorMessage) {
        assert(!result.success && result.message.stripRight == errorMessage);
    }

    void shouldFailure(REPLRunner.Result result) {
        assert(!result.success);
    }
}
