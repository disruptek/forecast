version = "1.0.3"
author = "disruptek"
description = "forecast"
license = "MIT"
requires "nim >= 0.20.0"
requires "https://github.com/disruptek/rest.git >= 1.0.0"
requires "https://github.com/disruptek/jsonconvert.git >= 1.0.0"

task test, "Runs the test suite":
  exec "nim c -d:ssl -r forecast.nim"
