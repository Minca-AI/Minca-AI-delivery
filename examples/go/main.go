// Command example-service is the Go fixture consumer of Minca-AI-delivery.
// `--help` is what the default image:smoke target calls; the flag package exits 0 on it.
package main

import (
	"flag"
	"fmt"
	"os"
)

// Greeting returns the greeting the service would serve.
func Greeting(name string) string {
	return fmt.Sprintf("hello, %s", name)
}

func main() {
	fs := flag.NewFlagSet("example-service", flag.ExitOnError)
	name := fs.String("name", "world", "who to greet")
	_ = fs.Parse(os.Args[1:])
	fmt.Println(Greeting(*name))
}
