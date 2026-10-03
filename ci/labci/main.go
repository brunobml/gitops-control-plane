// labci: lab CI helpers that need Argo CD / Kubernetes semantics (2026-10-03 Track A).
//
//	labci appsets -clusters ci/clusters.yaml [-revisions clusters/blueprint-revisions.env]
//	              [-repo <repoURL>=<dir> ...] <file.yaml>...
//	    Prints, as a YAML stream, every Application the given Applications/ApplicationSets produce.
//	    Fails on template errors (missingkey=error) and on duplicate Application names.
//
//	labci cel <file.yaml>...
//	    Compiles every CEL expression of ValidatingAdmissionPolicies with the Kubernetes CEL
//	    environment, and parses the CEL of Kyverno CEL policies (their custom functions are only
//	    known to Kyverno), without any cluster.
package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"sigs.k8s.io/yaml"
)

type multi []string

func (m *multi) String() string     { return strings.Join(*m, ",") }
func (m *multi) Set(v string) error { *m = append(*m, v); return nil }

func readDocs(file string) ([]map[string]any, error) {
	b, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var out []map[string]any
	for _, d := range bytes.Split(b, []byte("\n---")) {
		m := map[string]any{}
		if err := yaml.Unmarshal(d, &m); err != nil {
			return nil, fmt.Errorf("%s: %w", file, err)
		}
		if len(m) > 0 {
			out = append(out, m)
		}
	}
	return out, nil
}

func die(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "✘ "+format+"\n", a...)
	os.Exit(1)
}

func cmdAppsets(args []string) {
	fs := flag.NewFlagSet("appsets", flag.ExitOnError)
	clustersFile := fs.String("clusters", "", "cluster fixtures (YAML list)")
	revisions := fs.String("revisions", "", "clusters/blueprint-revisions.env: sets each cluster's blueprints-revision annotation")
	var repos multi
	fs.Var(&repos, "repo", "<repoURL>=<local dir> for git generators (repeatable)")
	_ = fs.Parse(args)

	ctx := &renderCtx{repos: map[string]string{}}
	if *clustersFile != "" {
		b, err := os.ReadFile(*clustersFile)
		if err != nil {
			die("%v", err)
		}
		if err := yaml.Unmarshal(b, &ctx.clusters); err != nil {
			die("%s: %v", *clustersFile, err)
		}
	}
	if *revisions != "" {
		f, err := os.Open(*revisions)
		if err != nil {
			die("%v", err)
		}
		rev := map[string]string{}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			l := strings.TrimSpace(sc.Text())
			if k, v, ok := strings.Cut(l, "="); ok && !strings.HasPrefix(l, "#") {
				rev[k] = v
			}
		}
		for i := range ctx.clusters {
			r, ok := rev[ctx.clusters[i].Name]
			if !ok {
				die("%s: no revision for cluster %s", *revisions, ctx.clusters[i].Name)
			}
			if ctx.clusters[i].Annotations == nil {
				ctx.clusters[i].Annotations = map[string]string{}
			}
			ctx.clusters[i].Annotations["blueprints-revision"] = r
		}
	}
	for _, r := range repos {
		k, v, ok := strings.Cut(r, "=")
		if !ok {
			die("-repo wants <repoURL>=<dir>, got %q", r)
		}
		ctx.repos[k] = v
	}

	seen := map[string]string{}
	var names []string
	var out bytes.Buffer
	for _, file := range fs.Args() {
		docs, err := readDocs(file)
		if err != nil {
			die("%v", err)
		}
		for _, d := range docs {
			apps, err := ctx.expand(d)
			if err != nil {
				die("%s: %v", file, err)
			}
			for _, a := range apps {
				n := fmt.Sprint(asMap(a["metadata"])["name"])
				if prev, dup := seen[n]; dup {
					die("duplicate Application name %q (%s and %s)", n, prev, file)
				}
				seen[n] = file
				names = append(names, n)
				b, _ := yaml.Marshal(a)
				out.WriteString("---\n")
				out.Write(b)
			}
		}
	}
	sort.Strings(names)
	fmt.Fprintf(os.Stderr, "✔ %d Applications: %s\n", len(names), strings.Join(names, " "))
	os.Stdout.Write(out.Bytes())
}

func main() {
	if len(os.Args) < 2 {
		die("usage: labci appsets|cel ...")
	}
	switch os.Args[1] {
	case "appsets":
		cmdAppsets(os.Args[2:])
	case "cel":
		cmdCel(os.Args[2:])
	default:
		die("unknown command %q", os.Args[1])
	}
}
