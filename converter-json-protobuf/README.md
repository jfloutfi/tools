## Protobuf JSON Converter

`convert_protobuf_json.py` converts protobuf payloads between binary wire format and JSON.

It is intended for cases where protobuf traffic needs to be inspected, edited, or replayed outside the application. A common workflow is:

1. Capture a protobuf request or response with a proxy tool such as Charles Proxy.
2. Decode the binary payload into JSON.
3. Edit the JSON payload.
4. Re-encode the JSON back into protobuf binary.
5. Use the modified payload for testing, for example through Charles Proxy Map Local.

This is also useful when generating or modifying test payloads against another repo that owns the protobuf schema, such as a service repo with shared API definitions.

## How It Works

The script resolves a target `.proto` file from `-root`, generates Python protobuf bindings with `protoc`, optionally exports Buf dependencies declared in `buf.lock`, and then converts payloads in either direction:

- binary protobuf to JSON
- JSON to binary protobuf

The message type is selected with the fully qualified protobuf name passed to `-message`.

## Generated Artifacts

The script creates generated artifacts in a workspace directory.

- Default workspace: `converter-json-protobuf/tmp/`
- Override with: `-tmp-dir`
- Buf exports are written under: `converter-json-protobuf/tmp/buf_exports/`
- The last used temp directory is recorded in: `converter-json-protobuf/.convert_protobuf_json.last_tmp_dir`

Cleanup behavior:

- `-cleanup` removes the directory provided with `-tmp-dir`
- otherwise it removes the last remembered temp directory if one was used
- otherwise it removes the default script-local `tmp/` directory

The default generated workspace and tracking file are already ignored by the repo `.gitignore`, so generated artifacts stay out of git by default.

## Command Arguments

- `-root`: base directory used to resolve proto files and imports
- `-tmp-dir`: optional directory for generated protobuf bindings and exported dependencies; defaults to script-local `tmp/`
- `-buf-lock`: optional path to the Buf lock file; defaults to `<root>/buf.lock` and is skipped if that default file does not exist
- `-proto-file`: path to the `.proto` file that defines the target message
- `-message`: fully qualified protobuf message name
- `-input-json`: JSON file to encode into protobuf binary
- `-output-bin`: output path for encoded protobuf binary
- `-input-bin`: protobuf binary file to decode
- `-output-json`: output path for decoded JSON
- `-allow-unknown-fields`: ignore unknown JSON fields while encoding
- `-regen`: regenerate generated protobuf Python bindings and Buf exports
- `-cleanup`: remove the resolved generated workspace

## Requirements

- Python 3
- `protobuf` Python package
- `protoc`
- `buf` if the target proto depends on modules declared in `buf.lock`

Example installation:

```bash
python3 -m pip install --user protobuf
brew install protobuf buf
```

## Examples

```bash
python3 converter-json-protobuf/convert_protobuf_json.py \
  -root . \
  -proto-file example/orders/v1/order_service.proto \
  -message example.orders.v1.GetOrderResponse \
  -input-bin example-order-response.bin \
  -output-json example-order-response.json
```

```bash
python3 converter-json-protobuf/convert_protobuf_json.py \
  -root . \
  -tmp-dir ./converter-json-protobuf/tmp \
  -proto-file example/orders/v1/order_service.proto \
  -message example.orders.v1.GetOrderResponse \
  -input-json example-order-response.json \
  -output-bin example-order-response.bin
```

```bash
python3 converter-json-protobuf/convert_protobuf_json.py \
  -root . \
  -buf-lock ./buf.lock \
  -proto-file example/orders/v1/order_service.proto \
  -message example.orders.v1.GetOrderResponse \
  -input-bin example-order-response.bin \
  -output-json example-order-response.json
```

```bash
python3 converter-json-protobuf/convert_protobuf_json.py -root . -cleanup
```
