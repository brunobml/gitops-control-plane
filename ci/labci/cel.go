package main

// Server-free CEL checks (2026-10-03 Track A.3).
//
//   - ValidatingAdmissionPolicy: compiled with the Kubernetes CEL compiler and environment
//     (k8s.io/apiserver, same library as the API server, NewExpressions mode, Kubernetes 1.35), in
//     the order the API server uses: variables first, then validations, messageExpressions,
//     auditAnnotations and matchConditions, each checked for its required result type. `object`
//     is untyped here (no OpenAPI schema), so field typos inside `object` are not caught; syntax,
//     functions, variables and result types are.
//   - Kyverno CEL policies (policies.kyverno.io): every expression is parsed. Kyverno adds its own
//     functions (images, verifyImageSignatures, ...), so only syntax is checked.
//   - kro ResourceGraphDefinition: the CEL inside every ${...} is parsed.

import (
	"fmt"
	"os"
	"strings"

	"github.com/google/cel-go/cel"
	"k8s.io/apimachinery/pkg/util/version"
	plugincel "k8s.io/apiserver/pkg/admission/plugin/cel"
	"k8s.io/apiserver/pkg/cel/environment"
)

type expr struct {
	name, text string
	types      []*cel.Type
}

func (e expr) GetExpression() string    { return e.text }
func (e expr) ReturnTypes() []*cel.Type { return e.types }
func (e expr) GetName() string          { return e.name }

var k8sVersion = version.MajorMinor(1, 35)

func list(v any) []map[string]any {
	var out []map[string]any
	a, _ := v.([]any)
	for _, x := range a {
		out = append(out, asMap(x))
	}
	return out
}

func checkVAP(obj map[string]any) []string {
	spec := asMap(obj["spec"])
	comp, err := plugincel.NewCompositedCompiler(environment.MustBaseEnvSet(k8sVersion))
	if err != nil {
		return []string{err.Error()}
	}
	opts := plugincel.OptionalVariableDeclarations{HasParams: spec["paramKind"] != nil, HasAuthorizer: true}
	var errs []string
	add := func(where string, r plugincel.CompilationResult) {
		if r.Error != nil {
			errs = append(errs, fmt.Sprintf("%s: %s", where, r.Error.Detail))
		}
	}
	var vars []plugincel.NamedExpressionAccessor
	for _, v := range list(spec["variables"]) {
		vars = append(vars, expr{name: fmt.Sprint(v["name"]), text: fmt.Sprint(v["expression"]), types: []*cel.Type{cel.AnyType}})
	}
	for _, v := range vars {
		add("variables."+v.GetName(), comp.CompileAndStoreVariable(v, opts, environment.NewExpressions))
	}
	for i, v := range list(spec["validations"]) {
		add(fmt.Sprintf("validations[%d].expression", i), comp.CompileCELExpression(expr{text: fmt.Sprint(v["expression"]), types: []*cel.Type{cel.BoolType}}, opts, environment.NewExpressions))
		if m, ok := v["messageExpression"].(string); ok {
			add(fmt.Sprintf("validations[%d].messageExpression", i), comp.CompileCELExpression(expr{text: m, types: []*cel.Type{cel.StringType}}, opts, environment.NewExpressions))
		}
	}
	for i, v := range list(spec["auditAnnotations"]) {
		add(fmt.Sprintf("auditAnnotations[%d]", i), comp.CompileCELExpression(expr{text: fmt.Sprint(v["valueExpression"]), types: []*cel.Type{cel.StringType, cel.NullType}}, opts, environment.NewExpressions))
	}
	for i, v := range list(spec["matchConditions"]) {
		add(fmt.Sprintf("matchConditions[%d]", i), comp.CompileCELExpression(expr{text: fmt.Sprint(v["expression"]), types: []*cel.Type{cel.BoolType}}, opts, environment.NewExpressions))
	}
	return errs
}

// collect returns every string under a key named like an expression field.
func collect(v any, path string, out map[string]string) {
	switch x := v.(type) {
	case map[string]any:
		for k, e := range x {
			if s, ok := e.(string); ok && (k == "expression" || k == "messageExpression" || k == "valueExpression") {
				out[path+"."+k] = s
				continue
			}
			collect(e, path+"."+k, out)
		}
	case []any:
		for i, e := range x {
			collect(e, fmt.Sprintf("%s[%d]", path, i), out)
		}
	}
}

// kroExprs returns the contents of every ${...} in string values, honouring nested braces.
func kroExprs(v any, path string, out map[string]string) {
	switch x := v.(type) {
	case string:
		for i, n := 0, 0; ; n++ {
			j := strings.Index(x[i:], "${")
			if j < 0 {
				return
			}
			start := i + j + 2
			depth, k := 1, start
			for ; k < len(x) && depth > 0; k++ {
				switch x[k] {
				case '{':
					depth++
				case '}':
					depth--
				}
			}
			if depth != 0 {
				out[fmt.Sprintf("%s#%d", path, n)] = x[start:] + " <unterminated ${>"
				return
			}
			out[fmt.Sprintf("%s#%d", path, n)] = x[start : k-1]
			i = k
		}
	case map[string]any:
		for k, e := range x {
			kroExprs(e, path+"."+k, out)
		}
	case []any:
		for i, e := range x {
			kroExprs(e, fmt.Sprintf("%s[%d]", path, i), out)
		}
	}
}

func parseAll(exprs map[string]string) []string {
	env, _ := cel.NewEnv()
	var errs []string
	for where, s := range exprs {
		if _, iss := env.Parse(s); iss.Err() != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", where, iss.Err()))
		}
	}
	return errs
}

func cmdCel(files []string) {
	failed, checked := 0, 0
	for _, f := range files {
		docs, err := readDocs(f)
		if err != nil {
			die("%v", err)
		}
		for _, d := range docs {
			api, kind := fmt.Sprint(d["apiVersion"]), fmt.Sprint(d["kind"])
			name := fmt.Sprint(asMap(d["metadata"])["name"])
			var errs []string
			switch {
			case kind == "ValidatingAdmissionPolicy" && strings.HasPrefix(api, "admissionregistration.k8s.io/"):
				errs = checkVAP(d)
			case strings.HasPrefix(api, "policies.kyverno.io/"):
				m := map[string]string{}
				collect(d["spec"], "spec", m)
				errs = parseAll(m)
			case kind == "ResourceGraphDefinition" && strings.HasPrefix(api, "kro.run/"):
				m := map[string]string{}
				kroExprs(d["spec"], "spec", m)
				errs = parseAll(m)
			default:
				continue
			}
			checked++
			if len(errs) > 0 {
				failed++
				for _, e := range errs {
					fmt.Fprintf(os.Stderr, "✘ %s %s/%s: %s\n", f, kind, name, e)
				}
			} else {
				fmt.Fprintf(os.Stderr, "✔ CEL %s/%s (%s)\n", kind, name, f)
			}
		}
	}
	if failed > 0 {
		die("CEL errors in %d of %d objects", failed, checked)
	}
	fmt.Fprintf(os.Stderr, "✔ CEL checked in %d objects\n", checked)
}
