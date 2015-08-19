/*
	Executable designed for plug in to the integration/validation suite.

	Reads yamelot on stdin; emits json on stdout.
*/
package main

import (
	"encoding/json"
	"io"
	"io/ioutil"
	"os"

	"github.com/dropbox/yamelot/go/yaml"
)

func main() {
	bounce(os.Stdin, os.Stdout)
}

func bounce(in io.Reader, out io.Writer) {
	input, err := ioutil.ReadAll(in)
	if err != nil {
		panic(err)
	}

	var value interface{}
	err = yaml.Unmarshal(input, &value)
	if err != nil {
		panic(err)
	}

	err = json.NewEncoder(out).Encode(value)
	if err != nil {
		panic(err)
	}
}
