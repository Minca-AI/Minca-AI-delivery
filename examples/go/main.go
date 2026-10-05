// Command example-service is the Go fixture consumer of Minca-AI-delivery.
// Its image is also the build-args fixture: the image build links the
// GREETING_NAME build argument in as defaultName, and image:smoke runs the
// fragment's `--help` smoke (the flag package exits 0 on it), then runs the
// image with no arguments and checks the greeting.
package main

import (
	"flag"
	"fmt"
	"os"
)

// defaultName is who to greet without -name. The image build sets it from the
// GREETING_NAME build argument (-ldflags -X main.defaultName=...); go run and
// go test keep "world".
var defaultName = "world"

// Greeting returns the greeting the service would serve.
func Greeting(name string) string {
	return fmt.Sprintf("hello, %s", name)
}

func main() {
	fs := flag.NewFlagSet("example-service", flag.ExitOnError)
	name := fs.String("name", defaultName, "who to greet")
	_ = fs.Parse(os.Args[1:])
	fmt.Println(Greeting(*name))
}
