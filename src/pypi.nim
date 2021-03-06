import
  asyncdispatch, httpclient, strutils, xmlparser, xmltree, json, mimetypes, os,
  ospaths, base64, tables, parseopt, terminal, random, times

const
  pypiApiUrl* = "https://pypi.org/"                             ## PyPI Base API URL.
  pypiXmlUrl = pypiApiUrl & "pypi"                              ## PyPI XML RPC API URL.
  pypiPackagesXml = "https://pypi.org/rss/packages.xml"         ## PyPI XML API URL.
  pypiUpdatesXml = "https://pypi.org/rss/updates.xml"           ## PyPI XML API URL.
  pypiUploadUrl = "https://test.pypi.org/legacy/"               ## PyPI Upload POST URL
  pypiJobUrl = "https://www.python.org/jobs/feed/rss/"          ## Python Jobs URL
  lppXml = "<methodName>list_packages</methodName>"             ## XML RPC Command.
  clsXml = "<methodName>changelog_last_serial</methodName>"     ## XML RPC Command.
  lpsXml = "<methodName>list_packages_with_serial</methodName>" ## XML RPC Command.
  xmlRpcParam = "<param><value><string>$1</string></value></param>"
  xmlRpcBody = "<?xml version='1.0'?><methodCall><methodName>$1</methodName><params>$2</params></methodCall>"
  hdrJson = {"dnt": "1", "accept": "application/json", "content-type": "application/json"}
  hdrXml  = {"dnt": "1", "accept": "text/xml", "content-type": "text/xml"}

let
  headerJson = newHttpHeaders(hdrJson)
  headerXml =  newHttpHeaders(hdrXml)

type
  PyPIBase*[HttpType] = object ## Base object.
    timeout*: byte  ## Timeout Seconds for API Calls, byte type, 0~255.
    proxy*: Proxy  ## Network IPv4 / IPv6 Proxy support, Proxy type.
  PyPI* = PyPIBase[HttpClient]           ##  Sync PyPI API Client.
  AsyncPyPI* = PyPIBase[AsyncHttpClient] ## Async PyPI API Client.

using
  classifiers: seq[string]
  project_name, project_version, package_name, user, release_version: string

template clientify(this: PyPI | AsyncPyPI): untyped =
  ## Build & inject basic HTTP Client with Proxy and Timeout.
  var client {.inject.} =
    when this is AsyncPyPI: newAsyncHttpClient(
      proxy = when declared(this.proxy): this.proxy else: nil, userAgent="")
    else: newHttpClient(
      timeout = when declared(this.timeout): this.timeout.int * 1_000 else: -1,
      proxy = when declared(this.proxy): this.proxy else: nil, userAgent="")

proc newPackages*(this: PyPI | AsyncPyPI): Future[XmlNode] {.multisync.} =
  ## Return an RSS XML XmlNode type with the Newest Packages uploaded to PyPI.
  clientify(this)
  client.headers = headerXml
  result =
    when this is AsyncPyPI: parseXml(await client.getContent(pypiPackagesXml))
    else: parseXml(client.getContent(pypiPackagesXml))

proc lastUpdates*(this: PyPI | AsyncPyPI): Future[XmlNode] {.multisync.} =
  ## Return an RSS XML XmlNode type with the Latest Updates uploaded to PyPI.
  clientify(this)
  client.headers = headerXml
  result =
    when this is AsyncPyPI: parseXml(await client.getContent(pypiUpdatesXml))
    else: parseXml(client.getContent(pypiUpdatesXml))

proc lastJobs*(this: PyPI | AsyncPyPI): Future[XmlNode] {.multisync.} =
  ## Return an RSS XML XmlNode type with the Latest Jobs posted to PyPI.
  clientify(this)
  client.headers = headerXml
  result =
    when this is AsyncPyPI: parseXml(await client.getContent(pypiJobUrl))
    else: parseXml(client.getContent(pypiJobUrl))

proc project*(this: PyPI | AsyncPyPI, project_name): Future[JsonNode] {.multisync.} =
  ## Return all JSON JsonNode type data for project_name from PyPI.
  clientify(this)
  client.headers = headerJson
  let url = pypiApiUrl & "pypi/" & project_name & "/json"
  result =
    when this is AsyncPyPI: parseJson(await client.getContent(url=url))
    else: parseJson(client.getContent(url=url))

proc release*(this: PyPI | AsyncPyPI, project_name, project_version): Future[JsonNode] {.multisync.} =
  ## Return all JSON data for project_name of an specific version from PyPI.
  clientify(this)
  client.headers = headerJson
  let url = pypiApiUrl & "pypi/" & project_name & "/" & project_version & "/json"
  result =
    when this is AsyncPyPI: parseJson(await client.getContent(url=url))
    else: parseJson(client.getContent(url=url))

proc htmlAllPackages*(this: PyPI | AsyncPyPI): Future[string] {.multisync.} =
  ## Return all projects registered on PyPI as HTML string,Legacy Endpoint,Slow.
  clientify(this)
  result =
    when this is AsyncPyPI: await client.getContent(url=pypiApiUrl & "simple")
    else: client.getContent(url=pypiApiUrl & "simple")

proc htmlPackage*(this: PyPI | AsyncPyPI, project_name): Future[string] {.multisync.} =
  ## Return a project registered on PyPI as HTML string, Legacy Endpoint, Slow.
  clientify(this)
  result =
    when this is AsyncPyPI: await client.getContent(url=pypiApiUrl & "simple/" & project_name)
    else: client.getContent(url=pypiApiUrl & "simple/" & project_name)

proc stats*(this: PyPI | AsyncPyPI): Future[JsonNode] {.multisync.} =
  ## Return all JSON stats data for project_name of an specific version from PyPI.
  clientify(this)
  client.headers = headerJson
  result =
    when this is AsyncPyPI: parseJson(await client.getContent(url=pypiApiUrl & "stats"))
    else: parseJson(client.getContent(url=pypiApiUrl & "stats"))

proc listPackages*(this: PyPI | AsyncPyPI): Future[seq[string]] {.multisync.} =
  ## Return 1 XML XmlNode of **ALL** the Packages on PyPI. Server-side Slow.
  clientify(this)
  client.headers = headerXml
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=lppXml))
    else: parseXml(client.postContent(pypiXmlUrl, body=lppXml))
  for tagy in response.findAll("string"):
    result.add tagy.innerText

proc changelogLastSerial*(this: PyPI | AsyncPyPI): Future[int] {.multisync.} =
  ## Return 1 XML XmlNode with the Last Serial number integer.
  clientify(this)
  client.headers = headerXml
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=clsXml))
    else: parseXml(client.postContent(pypiXmlUrl, body=clsXml))
  for tagy in response.findAll("int"):
    result = tagy.innerText.parseInt

proc listPackagesWithSerial*(this: PyPI | AsyncPyPI): Future[seq[array[2, string]]] {.multisync.} =
  ## Return 1 XML XmlNode of **ALL** the Packages on PyPI with Serial number integer. Server-side Slow.
  clientify(this)
  client.headers = headerXml
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=lpsXml))
    else: parseXml(client.postContent(pypiXmlUrl, body=lpsXml))
  for tagy in response.findAll("member"):
    result.add [tagy.child"name".innerText, tagy.child"value".child"int".innerText]

proc packageLatestRelease*(this: PyPI | AsyncPyPI, package_name): Future[string] {.multisync.} =
  ## Return the latest release registered for the given package_name.
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("package_releases", xmlRpcParam.format(package_name))
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))
  for tagy in response.findAll("string"):
    result = tagy.innerText

proc packageRoles*(this: PyPI | AsyncPyPI, package_name): Future[seq[XmlNode]] {.multisync.} =
  ## Retrieve a list of role, user for a given package_name. Role is Maintainer or Owner.
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("package_roles", xmlRpcParam.format(package_name))
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))
  for tagy in response.findAll("data"):
    result.add tagy

proc userPackages*(this: PyPI | AsyncPyPI, user): Future[seq[XmlNode]] {.multisync.} =
  ## Retrieve a list of role, package_name for a given user. Role is Maintainer or Owner.
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("user_packages", xmlRpcParam.format(user))
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))
  for tagy in response.findAll("data"):
    result.add tagy

proc releaseUrls*(this: PyPI | AsyncPyPI, package_name, release_version): Future[seq[string]] {.multisync.} =
  ## Retrieve a list of download URLs for the given release_version. Returns a list of dicts.
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("release_urls",
    xmlRpcParam.format(package_name) & xmlRpcParam.format(release_version))
  let response =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))
  for tagy in response.findAll("string"):
    if tagy.innerText.normalize.startsWith("http"):
      result.add tagy.innerText

proc releaseData*(this: PyPI | AsyncPyPI, package_name, release_version): Future[XmlNode] {.multisync.} =
  ## Retrieve metadata describing a specific release_version. Returns a dict.
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("release_data",
    xmlRpcParam.format(package_name) & xmlRpcParam.format(release_version))
  result =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))

proc search*(this: PyPI | AsyncPyPI, query: Table[string, seq[string]], operator="and"): Future[XmlNode] {.multisync.} =
  ## Search package database using indicated search spec. Returns 100 results max.
  doAssert operator in ["or", "and"], "operator must be 1 of 'and', 'or'."
  clientify(this)
  client.headers = headerXml
  let bodi = xmlRpcBody.format("search", xmlRpcParam.format(replace($query, "@", "")) & xmlRpcParam.format(operator))
  result =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))

proc browse*(this: PyPI | AsyncPyPI, classifiers): Future[XmlNode] {.multisync.} =
  ## Retrieve a list of name, version of all releases classified with all of given classifiers.
  ## Classifiers must be a list of standard Trove classifier strings. Returns 100 results max.
  doAssert classifiers.len > 1, "classifiers must be at least 2 strings lenght."
  clientify(this)
  client.headers = headerXml
  var clasifiers = ""
  for item in classifiers:
    clasifiers &= xmlRpcParam.format(item)
  let bodi = xmlRpcBody.format("browse", clasifiers)
  result =
    when this is AsyncPyPI: parseXml(await client.postContent(pypiXmlUrl, body=bodi))
    else: parseXml(client.postContent(pypiXmlUrl, body=bodi))

proc upload*(this: PyPI | AsyncPyPI,
             name, version, license, summary, description, author: string,
             downloadurl, authoremail, maintainer, maintaineremail: string,
             homepage, filename, md5_digest, username, password: string,
             keywords: seq[string],
             requirespython=">=3", filetype="sdist", pyversion="source",
             description_content_type="text/markdown; charset=UTF-8; variant=GFM",
             ): Future[string] {.multisync.} =
  ## Upload 1 new version of 1 registered package to PyPI from a local filename.
  ## PyPI Upload is HTTP POST with MultipartData with HTTP Basic Auth Base64.
  ## For some unknown reason intentionally undocumented (security by obscurity?)
  # https://warehouse.readthedocs.io/api-reference/legacy/#upload-api
  # github.com/python/cpython/blob/master/Lib/distutils/command/upload.py#L131-L135
  doAssert filename.existsFile, "filename must be 1 existent valid readable file"
  let
    fext = filename.splitFile.ext.toLowerAscii
    mime = newMimetypes().getMimetype(fext)
    auth = {"Authorization": "Basic " & encode(username & ":" & password), "dnt": "1"}
  # doAssert fext in ["whl", "egg", "zip"], "file extension must be 1 of .whl or .egg or .zip"
  var multipart_data = newMultipartData()
  multipart_data["protocol_version"] = "1"
  multipart_data[":action"] = "file_upload"
  multipart_data["metadata_version"] = "2.1"
  multipart_data["author"] = author
  multipart_data["name"] = name.normalize
  multipart_data["md5_digest"] = md5_digest # md5 hash of file in urlsafe base64
  multipart_data["summary"] = summary.normalize
  multipart_data["version"] = version.toLowerAscii
  multipart_data["license"] = license.toLowerAscii
  multipart_data["pyversion"] = pyversion.normalize
  multipart_data["requires_python"] = requirespython
  multipart_data["homepage"] = homepage.toLowerAscii
  multipart_data["filetype"] = filetype.toLowerAscii
  multipart_data["description"] = description.normalize
  multipart_data["keywords"] = keywords.join(" ").normalize
  multipart_data["download_url"] = downloadurl.toLowerAscii
  multipart_data["author_email"] = authoremail.toLowerAscii
  multipart_data["maintainer_email"] = maintaineremail.toLowerAscii
  multipart_data["description_content_type"] = description_content_type.strip
  multipart_data["maintainer"] = if maintainer == "": author else: maintainer
  multipart_data["content"] = (filename, mime, filename.readFile)
  when not defined(release): echo multipart_data.repr, "\n", auth
  clientify(this)
  client.headers = newHttpHeaders(auth)
  # result =  # TODO: Finish this and test against the test dev pypi server.
  #   when this is AsyncPyPI: await client.postContent(pypiUploadUrl, multipart=multipart_data)
  #   else: client.postContent(pypiUploadUrl, multipart=multipart_data)
  result = "result"


when isMainModule and not defined(release):
  let cliente = PyPI(timeout: 99)
  echo cliente.stats()
  echo cliente.newPackages()
  echo cliente.lastUpdates()
  echo cliente.listPackages()
  echo cliente.htmlAllPackages()
  echo cliente.changelogLastSerial()
  echo cliente.listPackagesWithSerial()
  echo cliente.project(project_name="pip")
  echo cliente.packageRoles(package_name="pip")
  echo cliente.userPackages(user="juancarlospaco")
  echo cliente.htmlPackage(project_name="requests")
  echo cliente.packageLatestRelease(package_name="pip")
  echo cliente.releaseUrls(package_name="pip", release_version="18.1")
  echo cliente.releaseData(package_name="pip", release_version="18.1")
  echo cliente.release(project_name="microraptor", project_version="2.0.0")
  #echo cliente.search({"name": @["requests"]}.toTable)
  #echo cliente.browse(@["Topic :: Utilities", "Topic :: System"])
  # echo cliente.upload(
  #   username        = "user",
  #   password        = "s3cr3t",
  #   name            = "TestPackage",
  #   version         = "0.0.1",
  #   license         = "MIT",
  #   summary         = "A test package for testing purposes",
  #   description     = "A test package for testing purposes",
  #   author          = "Juan Carlos",
  #   downloadurl     = "https://www.example.com/download",
  #   authoremail     = "author@example.com",
  #   maintainer      = "Juan Carlos",
  #   maintaineremail = "maintainer@example.com",
  #   homepage        = "https://www.example.com",
  #   filename        = "pypi.nim",
  #   md5_digest      = "4266642",
  #   keywords        = @["test", "testing"],
  # )
else:
  {.passL: "-s", passC: "-flto -ffast-math", optimization: size.}
  const
    helpy = "PIP/PyPI-Client Alternative,x20 Faster,x50 Smaller,Lib 99% Complete,App 0% Complete,WIP."
  var
    taimaout = 99.byte
    user: string
    debug: bool
  for tipoDeClave, clave, valor in getopt():
    case tipoDeClave
    of cmdShortOption, cmdLongOption:
      case clave
      of "version":              quit("0.1.0", 0)
      of "license", "licencia":  quit("MIT", 0)
      of "help", "ayuda":        quit(helpy, 0)
      of "timeout":              taimaout = valor.parseInt.byte
      of "user", "usuario":      user = valor.string.normalize
      of "debug", "desbichar":   debug = true
      of "color":
        randomize()
        setBackgroundColor(bgBlack)
        setForegroundColor([fgRed, fgGreen, fgYellow, fgBlue, fgMagenta, fgCyan, fgWhite].rand)
    of cmdArgument:
      comando = clave.string.normalize
    of cmdEnd: quit("Wrong Parameters, please see Help with: --help", 1)
