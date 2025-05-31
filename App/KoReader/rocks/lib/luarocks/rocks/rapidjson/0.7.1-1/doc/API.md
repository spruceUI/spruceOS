# Lua RapidJSON API Reference

## rapidjson.decode()

Decode JSON to Lua table.

### Synopsis

```Lua
value = rapidjson.decode(jsonstring)
value = rapidjson.decode(lightuserdata, length)
```

### Arguments

**jsonstring**

A JSON value string to be decoded.

**lightuserdata**

The C buffer start address.

**length**

The C buffer length.

### Returns

Return table if JSON is an object or array.

Return `true`, `false`, number and `rapidjson.null` respectively if JSON is a simple value.

Return nil plus an error message as a second result when passed string is not a valid JSON.


### Errors

- When passed value is not (convertible to) string.


## rapidjson.encode()

Encode Lua table to JSON string.

supports the following types:

* boolean
* rapidjson.null
* number
* string
* table

The JSON object keys are sorted by the this function.

### Synopsis

```Lua
string = rapidjson.encode(value [, option])
```

### Arguments  

**value**:

When passed a table:

1. it is encoded as JSON array if:
    - meta field `__jsontype` set to `array`.
    - table contains length > 0.
2. otherwise the table is encoded as JSON object and non string keys and its values are ignored.

When passed with `true`, `false`, number and `rapidjson.null`, simply encode as simple JSON value.

**option**:

A optional table contains follow field:

* `pretty` boolean: Set `true` to make output string to be pretty formated. Default is false.
* `sort_keys` boolean: Set `true` to make JSON object keys be sorted. Default is `false`.
* `empty_table_as_array` boolean: Set `true` to make empty table encode as JSON array. Default is `false`.

### Returns

Return stringified JSON on success.
Return nil on failure, plus an error message as a second result.



### Errors

* When option passed a value other than table.


### Examples

```Lua
local rapidjson = require('rapidjson')

rapidjson.encode({})     -- '{}'

rapidjson.encode(rapidjson.object()) --> '{}'
rapidjson.encode(rapidjson.array()) --> '[]'

rapidjson.encode(setmetatable({}, {__jsontype='object'})) --> '{}'
rapidjson.encode(setmetatable({}, {__jsontype='array'})) --> '[]'

rapidjson.encode(true) --> 'true'
rapidjson.encode(rapidjson.null) --> 'null'
rapidjson.encode(123) --> '123.0' or '123' in Lua 5.3.


rapidjson.encode({true, false}) --> '[true, false]'

rapidjson.encode({a=true, b=false}) --> '{"a":true,"b":false]'

```


## rapidjson.load()

Load JSON file into Lua table.

### Synopsis

```Lua
value = rapidjson.load(filename)
```

### Arguments

**filename**

JSON file to be loaded.

### Returns

Return table if file contains an object or array.

Return `true`, `false`, number and `rapidjson.null` respectively if file contains a simple value.

Return nil plus an error message as a second result when passed file is not valid JSON file.


### Errors

- When passed filename is not (convertible to) string.



## rapidjson.dump()

Dump Lua value to JSON file.

### Synopsis

```Lua
success, err = rapidjson.dump(value, filename [, option])
```

### Arguments


**value**

Same as in `rapidjson.encode()`.

**filename**

The file path string where to save encode json string.


**option**:

Same as in options in `rapidjson.encode()`.

### Returns

bool: success

Return true on success.

Return false plus an error message as a second result when:

- Value can't be encoded.
- `filename` can't be opened for write.

### Error

* When passed filename is not (convertible to) string.
* When passed option is not table, nil or none.


### Example

```Lua
local rapidjson = require('rapidjson')

rapidjson.dump({rapidjson.null}, 'test.json')
rapidjson.dump({rapidjson.null}, 'test-pretty.json', {pretty=true})

```

## rapidjson.null

The placeholder for null values in rapidjson.

eg.

```Lua
local rapidjson = require('rapidjson')

rapidjson.decode('[null]') --> {rapidjson.null}
rapidjson.encode({rapidjson.null}) --> '[null]'

```

## rapidjson.object()

Create a new empty table that have metatable field `__jsontype` set as `'object'` so that the `encode` and `dump` function will encode it as JSON object.

When passed an valid table:

* Passed table do not have metatable, just set above metatable for the table.
* Passed table already have metatable, set the metatable field `__jsontype` to 'object'.

### Synopsis

```Lua
obj = rapidjson.object([t])
```

### Arguments

*t*

Optional table to be set the metatable with meta field `__jsontype` set as `'object'`.

### Returns

Origin passed in table when passed with a table.
Or new created table.


## rapidjson.array()

Same as rapidjson.array() except the metatable field `__jsontype` is set as `'array'`. And the `encode` and `dump` function will encode it as JSON array.


## rapidjson.Document()

Creates a rapidjson Document object. Optionally create from a Lua table or string of JSON document.

### Synopsis

```Lua
doc = rapidjson.Document([t|s])
```


### Arguments

*t*

Optional table to be create a rapidjson Document from.

*s*

Optional a string contains a JSON document, then when document created the string is parsed into the document.

## document:parse()

Parse JSON document contained in string s.

### Synopsis

```Lua
local ok, message = document:parse(s)
```

### Arguments

*s*

A string contains a JSON document.

### Returns

Returns `true` on success. Otherwise `false` and an additional error message is returned.


### Usage Examples

```lua
local rapidjson = require('rapidjson')
local doc = rapidjson.Document()
local ok, message = doc:parse('{"a":["appke", "air"]}')
if not ok then
  print(message)
end
```


## document:get()

Get document member by [JSON Pointer](http://rapidjson.org/md_doc_pointer.html).


### Synopsis

```Lua
local value = document:get(pointer[, default])
```

### Arguments

*pointer*

A string contains JSON pointer.

*default*

The default value to return if the document does not contains value specified by the pointer.


### Returns

It document have elements specified by pointer, the element value is returned as a Lua value.
Otherwise, `default` value is returned; if `default` is not specified, `nil` is returned.


## document:set()

Set document member by [JSON Pointer](http://rapidjson.org/md_doc_pointer.html) with specified value.


### Synopsis

```Lua
document:set(pointer, value)
```

### Arguments

*pointer*

A string contains JSON pointer.

*value*

The value to set as new value for document element specified by pointer.

### Examples

```lua
local doc = rapidjson.Document()
doc:set('/a', {'apple', 'air'})
```

## rapidjson.SchemaDocument()

Creates a SchemaDocument from Document or a Lua table or a string contains a JSON schema.

### Synopsis

```lua
local sd = rapidjson.SchemaDocument(doc|t|s)
```

### Arguments

*doc*

The the JSON schema stored in rapidjson.Document object.

*t*

The Lua table representation of a JSON schema.

*s*

The string contains a JSON schema.

### Returns

Returns the new SchemaDocument object.


### Example

```lua
local d = rapidjson.Document('{"type": ["string", "number"]}')
local sd = rapidjson.SchemaDocument(d)
```

```lua
local sd = rapidjson.SchemaDocument({type= {"string", "number"}})
```

```lua
local sd = rapidjson.SchemaDocument('{"type": ["string", "number"]}')
```

## rapidjson.SchemaValidator()

Creates a SchemaValidator from a SchemaDocument.

### Synopsis

```lua
local validator = apidjson.SchemaValidator(sd)
```

### Arguments

*sd*

The SchemaDocument to create the validator. SchemaDocument can be shared by schema validators.

### Returns

Returns the new created validator object.

### Example

```lua
local sd = rapidjson.SchemaDocument('{"type": ["string", "number"]}')
local validator = rapidjson.SchemaValidator(sd)

local d = rapidjson.Document('.....')

local ok, message = validator:validate(d)
```

## SchemaValidator:validate()

Validates a JSON document.

### Synopsis

```lua
local ok, message = validator:validate(d)
```

### Arguments

*d*

The document to be validated against the schema stored inside the validator.

### Returns

Returns `true` if the document is valid. Otherwise returns `false` and a extra error message.


## rapidjson.\_NAME

A string that is `"rapidjson"`.

## rapidjson.\_VERSION

The current loaded rapidjson version. `"scm"` when not build with luarocks.
