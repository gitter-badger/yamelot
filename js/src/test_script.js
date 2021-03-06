var fs = require('fs');
var indentParser = require('./indent.js');
var yamelotParser = require('./grammar.js');

process.argv.slice(2).forEach(function (fileName) {
    var text = fs.readFileSync(fileName, "utf8");
    var indentedText = indentParser.parse(text);
    console.log('============== Indented')
    console.log(indentedText)
    var output = yamelotParser.parse(indentedText);
    console.log('============== Parsed')
    console.log(output)
});
