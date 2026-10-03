package main

// Offline ApplicationSet rendering (2026-10-03 Track A.1).
//
// Renders every Application and ApplicationSet the way the Argo CD ApplicationSet controller does
// for the generators this lab uses (clusters, list, matrix, git files), so CI sees the same
// Applications the hub would create:
//   - goTemplate with text/template + sprig, minus the functions Argo CD removes (env, expandenv,
//     getHostByName), plus normalize/slugify/toYaml/fromYaml/fromYamlArray;
//   - goTemplateOptions (missingkey=error) honoured, so a registration with a missing field fails
//     here exactly as it would freeze the real ApplicationSet (assessment L2-3);
//   - every string value of spec.template is rendered (keys are not), as Argo CD does.
// Cluster generator input is ci/clusters.yaml (the cluster Secrets register-spokes.sh creates).
// Git files generator input is a local checkout of the generator's repository.

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"text/template"

	"github.com/Masterminds/sprig/v3"
	"sigs.k8s.io/yaml"
)

type cluster struct {
	Name        string            `json:"name"`
	Server      string            `json:"server"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
}

type renderCtx struct {
	clusters []cluster
	repos    map[string]string // repoURL -> local checkout (git files generator)
}

var nonAlnum = regexp.MustCompile(`[^a-zA-Z0-9-.]+`)

func normalize(s string) string {
	return strings.Trim(strings.ToLower(nonAlnum.ReplaceAllString(s, "-")), "-.")
}

func funcMap() template.FuncMap {
	f := sprig.TxtFuncMap()
	for _, k := range []string{"env", "expandenv", "getHostByName"} {
		delete(f, k)
	}
	f["normalize"] = normalize
	f["slugify"] = func(args ...any) string { return normalize(fmt.Sprint(args[len(args)-1])) }
	f["toYaml"] = func(v any) (string, error) {
		b, err := yaml.Marshal(v)
		return strings.TrimSuffix(string(b), "\n"), err
	}
	f["fromYaml"] = func(s string) (map[string]any, error) {
		m := map[string]any{}
		err := yaml.Unmarshal([]byte(s), &m)
		return m, err
	}
	f["fromYamlArray"] = func(s string) ([]any, error) { var a []any; err := yaml.Unmarshal([]byte(s), &a); return a, err }
	return f
}

func renderString(s string, params map[string]any, opts []string) (string, error) {
	if !strings.Contains(s, "{{") {
		return s, nil
	}
	t, err := template.New("").Funcs(funcMap()).Option(opts...).Parse(s)
	if err != nil {
		return "", err
	}
	var b bytes.Buffer
	if err := t.Execute(&b, params); err != nil {
		return "", err
	}
	return b.String(), nil
}

func renderTree(v any, params map[string]any, opts []string) (any, error) {
	switch x := v.(type) {
	case string:
		return renderString(x, params, opts)
	case map[string]any:
		out := map[string]any{}
		for k, e := range x {
			r, err := renderTree(e, params, opts)
			if err != nil {
				return nil, err
			}
			out[k] = r
		}
		return out, nil
	case []any:
		out := make([]any, len(x))
		for i, e := range x {
			r, err := renderTree(e, params, opts)
			if err != nil {
				return nil, err
			}
			out[i] = r
		}
		return out, nil
	}
	return v, nil
}

func asMap(v any) map[string]any { m, _ := v.(map[string]any); return m }

func matchSelector(sel map[string]any, labels map[string]string) (bool, error) {
	for k, v := range asMap(sel["matchLabels"]) {
		if labels[k] != fmt.Sprint(v) {
			return false, nil
		}
	}
	exprs, _ := sel["matchExpressions"].([]any)
	for _, e := range exprs {
		em := asMap(e)
		key := fmt.Sprint(em["key"])
		val, has := labels[key]
		var vals []string
		for _, x := range em["values"].([]any) {
			vals = append(vals, fmt.Sprint(x))
		}
		in := false
		for _, x := range vals {
			in = in || x == val
		}
		switch em["operator"] {
		case "In":
			if !has || !in {
				return false, nil
			}
		case "NotIn":
			if has && in {
				return false, nil
			}
		case "Exists":
			if !has {
				return false, nil
			}
		case "DoesNotExist":
			if has {
				return false, nil
			}
		default:
			return false, fmt.Errorf("unsupported selector operator %v", em["operator"])
		}
	}
	return true, nil
}

func (c *renderCtx) generate(g map[string]any) ([]map[string]any, error) {
	switch {
	case g["list"] != nil:
		var out []map[string]any
		for _, e := range asMap(g["list"])["elements"].([]any) {
			out = append(out, asMap(e))
		}
		return out, nil
	case g["clusters"] != nil:
		sel := asMap(asMap(g["clusters"])["selector"])
		var out []map[string]any
		for _, cl := range c.clusters {
			ok, err := matchSelector(sel, cl.Labels)
			if err != nil {
				return nil, err
			}
			if !ok {
				continue
			}
			labels, ann := map[string]any{}, map[string]any{}
			for k, v := range cl.Labels {
				labels[k] = v
			}
			for k, v := range cl.Annotations {
				ann[k] = v
			}
			out = append(out, map[string]any{
				"name": cl.Name, "nameNormalized": normalize(cl.Name), "server": cl.Server, "project": "",
				"metadata": map[string]any{"labels": labels, "annotations": ann},
			})
		}
		return out, nil
	case g["matrix"] != nil:
		gens := asMap(g["matrix"])["generators"].([]any)
		if len(gens) != 2 {
			return nil, fmt.Errorf("matrix needs exactly 2 generators")
		}
		a, err := c.generate(asMap(gens[0]))
		if err != nil {
			return nil, err
		}
		b, err := c.generate(asMap(gens[1]))
		if err != nil {
			return nil, err
		}
		var out []map[string]any
		for _, x := range a {
			for _, y := range b {
				m := map[string]any{}
				for k, v := range x {
					m[k] = v
				}
				for k, v := range y {
					m[k] = v
				}
				out = append(out, m)
			}
		}
		return out, nil
	case g["git"] != nil:
		gm := asMap(g["git"])
		repo := fmt.Sprint(gm["repoURL"])
		dir, ok := c.repos[repo]
		if !ok {
			return nil, fmt.Errorf("git generator: no local checkout for %s (use -repo %s=<dir>)", repo, repo)
		}
		files, _ := gm["files"].([]any)
		if len(files) == 0 {
			return nil, fmt.Errorf("git generator: only the files form is supported")
		}
		var out []map[string]any
		for _, f := range files {
			matches, err := filepath.Glob(filepath.Join(dir, fmt.Sprint(asMap(f)["path"])))
			if err != nil {
				return nil, err
			}
			sort.Strings(matches)
			for _, m := range matches {
				b, err := os.ReadFile(m)
				if err != nil {
					return nil, err
				}
				p := map[string]any{}
				if err := yaml.Unmarshal(b, &p); err != nil {
					return nil, fmt.Errorf("%s: %w", m, err)
				}
				rel, _ := filepath.Rel(dir, m)
				d := path.Dir(filepath.ToSlash(rel))
				var segs []any
				for _, s := range strings.Split(d, "/") {
					segs = append(segs, s)
				}
				p["path"] = map[string]any{
					"path": d, "basename": path.Base(d), "filename": path.Base(rel),
					"basenameNormalized": normalize(path.Base(d)), "filenameNormalized": normalize(path.Base(rel)),
					"segments": segs,
				}
				out = append(out, p)
			}
		}
		return out, nil
	}
	return nil, fmt.Errorf("unsupported generator %v", keys(g))
}

func keys(m map[string]any) []string {
	var k []string
	for x := range m {
		k = append(k, x)
	}
	sort.Strings(k)
	return k
}

// expand returns the Applications an object produces: itself for an Application, the generated
// ones for an ApplicationSet.
func (c *renderCtx) expand(obj map[string]any) ([]map[string]any, error) {
	switch obj["kind"] {
	case "Application":
		return []map[string]any{obj}, nil
	case "ApplicationSet":
	default:
		return nil, nil
	}
	spec := asMap(obj["spec"])
	name := fmt.Sprint(asMap(obj["metadata"])["name"])
	if spec["goTemplate"] != true {
		return nil, fmt.Errorf("ApplicationSet %s: goTemplate is required by platform policy", name)
	}
	var opts []string
	if o, ok := spec["goTemplateOptions"].([]any); ok {
		for _, x := range o {
			opts = append(opts, fmt.Sprint(x))
		}
	}
	var apps []map[string]any
	for _, g := range spec["generators"].([]any) {
		params, err := c.generate(asMap(g))
		if err != nil {
			return nil, fmt.Errorf("ApplicationSet %s: %w", name, err)
		}
		for _, p := range params {
			r, err := renderTree(spec["template"], p, opts)
			if err != nil {
				return nil, fmt.Errorf("ApplicationSet %s: template: %w", name, err)
			}
			app := map[string]any{"apiVersion": "argoproj.io/v1alpha1", "kind": "Application"}
			for k, v := range asMap(r) {
				app[k] = v
			}
			md := asMap(app["metadata"])
			if md == nil {
				md = map[string]any{}
				app["metadata"] = md
			}
			ann := asMap(md["annotations"])
			if ann == nil {
				ann = map[string]any{}
				md["annotations"] = ann
			}
			ann["ci.lab/generated-by"] = name
			apps = append(apps, app)
		}
	}
	return apps, nil
}
