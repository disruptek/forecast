import os
import times
import json
import httpclient
import uri
import httpcore
import strformat
import strutils

import rest
export rest

import jsonconvert

const
  forecastMinutely {.booldefine.} = false

type
  ResultPage* = JsonNode

  Url = string
  DarkSkyClient* = object of RestClient
  DarkSkyError* = object of CatchableError       ## base for Dark Sky errors
  ParseError* = object of DarkSkyError           ## misc parse failure
    parsed*: ResultPage
    text*: string
  ErrorResponse* = object of ParseError          ## unwrap error response
    ShortMessage*: string
    LongMessage*: string
    ErrorCode*: string
    ErrorParameters*: ResultPage
  DarkSkyForecast* = ref object of RestCall
  DarkSkyTimeMachine* = ref object of RestCall
  Coords* = object of RootObj
    latitude*: float
    longitude*: float
  Icon* = enum
    ClearDay = "clear-day",
    ClearNight = "clear-night",
    Rain = "rain",
    Snow = "snow",
    Sleet = "sleet",
    Wind = "wind",
    Fog = "fog",
    Cloudy = "cloudy",
    PartlyCloudyDay = "partly-cloudy-day",
    PartlyCloudyNight = "partly-cloudy-night"

  Precip* {.pure.} = enum
    Rain = "rain",
    Snow = "snow",
    Sleet = "sleet"

  PointKind* = enum Current, Minute, Hourly, Daily
  DataPoint* = object of RootObj
    time*: DateTime
    cloudCover*: float
    dewPoint*: float
    humidity*: float
    icon*: Icon
    ozone*: float
    precipIntensity*: float
    precipIntensityError*: float
    precipProbability*: float
    precipType*: Precip
    pressure*: float
    summary*: string
    uvIndex*: int
    visibility*: float
    windBearing*: int
    windGust*: float
    windSpeed*: float
    # only hourly or daily -- maybe only historical?
    precipAccumulation*: float
    case kind*: PointKind
    of Current:
      nearestStormBearing*: float
      nearestStormDistance*: float
    of Minute:
      discard
    of Hourly:
      apparentTemperature*: float
      temperature*: float
    of Daily:
      windGustTime*: DateTime
      uvIndexTime*: DateTime
      sunriseTime*: DateTime
      sunsetTime*: DateTime
      apparentTemperatureHigh*: float
      apparentTemperatureHighTime*: DateTime
      apparentTemperatureLow*: float
      apparentTemperatureLowTime*: DateTime
      apparentTemperatureMax*: float
      apparentTemperatureMaxTime*: DateTime
      apparentTemperatureMin*: float
      apparentTemperatureMinTime*: DateTime
      temperatureHigh*: float
      temperatureHighTime*: DateTime
      temperatureLow*: float
      temperatureLowTime*: DateTime
      temperatureMax*: float
      temperatureMaxTime*: DateTime
      temperatureMin*: float
      temperatureMinTime*: DateTime
      moonPhase*: float
      precipIntensityMax*: float
      precipIntensityMaxTime*: DateTime

  DataBlock* = object of RootObj
    summary*: string
    icon*: Icon
    data*: seq[DataPoint]
  Flags* = object of RootObj
    sources*: seq[string]
    nearest*: float
    units*: string
  WeatherReport* = object of RootObj
    timezone*: string
    latitude*: float
    longitude*: float
    currently*: DataPoint
    daily*: DataBlock
    hourly*: DataBlock
    flags*: Flags
    when forecastMinutely:
      minutely*: DataBlock

let Forecast* = DarkSkyForecast(name: "Forecast")
let TimeMachine* = DarkSkyTimeMachine(name: "TimeMachine")

proc `$`*(c: Coords): string =
  result = &"{c.latitude:3.4f},{c.longitude:3.4f}"

converter toCoords*(s: string): Coords =
  let parts = s.split(',')
  result = Coords()
  result.latitude = parts[0].parseFloat()
  result.longitude = parts[1].parseFloat()

proc `$`*(e: ref DarkSkyError): string
  {.raises: [].}=
  result = $typeof(e) & " " & e.msg

proc `$`*(e: ref ParseError): string
  {.raises: [].}=
  result = $typeof(e) & " " & e.msg & "\n" & $e.text

proc `$`*(e: ref ErrorResponse): string
  {.raises: [].} =
  result = $typeof(e) & " " & e.msg & "\n" & $e.parsed

proc default_endpoint*(name: Url=""): string =
  let key = cast[string](os.getEnv("DARKSKYAPI")).encodeUrl(usePlus=false)
  if name == "":
    result = &"https://api.darksky.net/forecast/{key}"
  else:
    result = name & "/" & key

method recall*(call: DarkSkyForecast; input: Coords): Recallable
  {.base, raises: [Exception].} =
  ## issue a retryable Forecast to Dark Sky
  let
    base = default_endpoint()
    url = base & "/" & $input

  result = call.newRecallable(url.parseUri, headers={
    "Content-Type": "application/json;charset=UTF-8",
  }, body="")
  result.meth = HttpGet

proc inZone(js: JsonNode; tz: Timezone; name="time"): DateTime =
  result = js.get(name, 0).fromUnix().inZone(tz)

proc populate(self: var DataPoint; js: JsonNode) =
  self.cloudCover = js.get("cloudCover", 0.0)
  self.dewPoint = js.get("dewPoint", 0.0)
  self.humidity = js.get("humidity", 0.0)
  self.icon = js.get("icon", Icon.ClearDay)
  self.ozone = js.get("ozone", 0.0)
  self.precipIntensity = js.get("precipIntensity", 0.0)
  self.precipIntensityError = js.get("precipIntensityError", 0.0)
  self.precipProbability = js.get("precipProbability", 0.0)
  self.precipType = js.get("precipType", Precip.Rain)
  self.pressure = js.get("pressure", 0.0)
  self.summary = js.get("summary", "")
  self.uvIndex = js.get("uvIndex", 0)
  self.visibility = js.get("visibility", 0.0)
  self.windBearing = js.get("windBearing", 0)
  self.windGust = js.get("windGust", 0.0)
  self.windSpeed = js.get("windSpeed", 0.0)
  case self.kind:
    of Current:
      self.nearestStormBearing = js.get("nearestStormBearing", 0.0)
      self.nearestStormDistance = js.get("nearestStormDistance", 0.0)
    of Minute:
      discard
    of Hourly:
      self.apparentTemperature = js.get("apparentTemperature", 0.0)
      self.temperature = js.get("temperature", 0.0)
      self.precipAccumulation = js.get("precipAccumulation", 0.0)
    of Daily:
      self.precipAccumulation = js.get("precipAccumulation", 0.0)
      self.apparentTemperatureHigh = js.get("apparentTemperatureHigh", 0.0)
      self.apparentTemperatureLow = js.get("apparentTemperatureLow", 0.0)
      self.apparentTemperatureMax = js.get("apparentTemperatureMax", 0.0)
      self.apparentTemperatureMin = js.get("apparentTemperatureMin", 0.0)
      self.temperatureHigh = js.get("temperatureHigh", 0.0)
      self.temperatureLow = js.get("temperatureLow", 0.0)
      self.temperatureMax = js.get("temperatureMax", 0.0)
      self.temperatureMin = js.get("temperatureMin", 0.0)
      self.moonPhase = js.get("moonPhase", 0.0)
      self.precipIntensityMax = js.get("precipIntensityMax", 0.0)

proc newPoint(kind: PointKind; tz: Timezone; js: JsonNode): DataPoint =
  var t: DateTime = js.inZone(tz, "time")
  result = case kind:
    of Current:
      DataPoint(kind: Current, time: t)
    of Minute:
      DataPoint(kind: Minute, time: t)
    of Hourly:
      DataPoint(kind: Hourly, time: t)
    of Daily:
      DataPoint(kind: Daily, time: t,
        sunsetTime: js.inZone(tz, "sunsetTime"),
        sunriseTime: js.inZone(tz, "sunriseTime"),
        uvIndexTime: js.inZone(tz, "uvIndexTime"),
        windGustTime: js.inZone(tz, "windGustTime"),
        apparentTemperatureHighTime: js.inZone(tz, "apparentTemperatureHighTime"),
        apparentTemperatureLowTime: js.inZone(tz, "apparentTemperatureLowTime"),
        apparentTemperatureMaxTime: js.inZone(tz, "apparentTemperatureMaxTime"),
        apparentTemperatureMinTime: js.inZone(tz, "apparentTemperatureMinTime"),
        temperatureHighTime: js.inZone(tz, "temperatureHighTime"),
        temperatureLowTime: js.inZone(tz, "temperatureLowTime"),
        temperatureMaxTime: js.inZone(tz, "temperatureMaxTime"),
        temperatureMinTime: js.inZone(tz, "temperatureMinTime"),
        precipIntensityMaxTime: js.inZone(tz, "precipIntensityMaxTime"),
      )
  result.populate(js)

proc newBlock(kind: PointKind; tz: Timezone; js: JsonNode): DataBlock =
  result = DataBlock(
    summary: js.get("summary", ""),
    icon: js.get("icon", Icon.ClearDay)
  )
  for item in js["data"].items:
    result.data.add kind.newPoint(tz, item)

converter toReport*(js: JsonNode): WeatherReport =
  let
    offset = js.get("offset", 0)
    timezone = js.get("timezone", "")
  proc someTzInfo(time: Time): ZonedTime =
    ZonedTime(utcOffset: offset * -3600, isDst: true, time: time)
  let tz = newTimezone(timezone, someTzInfo, someTzInfo)
  var currently = Current.newPoint(tz, js["currently"])
  result = WeatherReport(currently: currently)
  when forecastMinutely:
    result.minutely = Minute.newBlock(tz, js["minutely"])
  result.hourly = Hourly.newBlock(tz, js["hourly"])
  result.daily = Daily.newBlock(tz, js["daily"])
  result.timezone = js.get("timezone", "")
  result.latitude = js.get("latitude", 0.0)
  result.longitude = js.get("longitude", 0.0)

converter toReport*(s: string): WeatherReport =
  let js = s.parseJson()
  result = js.toReport()


when isMainModule:
  import asyncdispatch
  import logging

  let logger = newConsoleLogger(useStderr=true)
  addHandler(logger)

  var
    response: AsyncResponse
    rec: Recallable
    text: string

  let coords = cast[string](os.getEnv("LATLONG")).toCoords()
  rec = Forecast.recall(coords)
  try:
    response = rec.retried()
  except RestError as e:
    debug "rest error:", e
  text = waitFor response.body
  echo text
