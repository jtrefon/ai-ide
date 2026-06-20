# Gemma 4 E4B — Complete Reference

Sources: tokenizer_config.json, chat_template.jinja, config.json (from the MLX 4-bit model)

## Special Tokens

| ID  | Token              | Name            | Notes             |
|-----|--------------------|-----------------|-------------------|
| 0   | `<pad>`            | pad_token       |                   |
| 1   | `<eos>`            | eos_token       | **EOS**           |
| 2   | `<bos>`            | bos_token       |                   |
| 3   | `<unk>`            | unk_token       |                   |
| 4   | `<mask>`           | mask_token      |                   |
| 46  | `<\|tool>`         | std_token       | tool decl start   |
| 47  | `<tool\|>`         | etd_token       | tool decl end     |
| 48  | `<\|tool_call>`    | stc_token       | tool call start   |
| 49  | `<tool_call\|>`    | etc_token       | tool call end     |
| 50  | `<\|tool_response>`| str_token       | tool rsp start    |
| 51  | `<tool_response\|>`| etr_token       | tool rsp end      |
| 52  | `<\|"\|>`          | escape_token    | string delimiter  |
| 98  | `<\|think\|>`      | think_token     | thinking mode     |
| 100 | `<\|channel>`      | soc_token       | channel start     |
| 101 | `<channel\|>`      | eoc_token       | channel end       |
| 105 | `<\|turn>`         | sot_token       | turn start        |
| 106 | `<turn\|>`         | eot_token       | turn end **EOS**  |

**EOS tokens**: [1, 106, 50] — `<eos>`, `<turn\|>`, and `<\|tool_response>` all terminate generation.

## Chat Prompt Format

```
<bos><|turn>system\n
[<|think|>]                                                   # if thinking enabled
<system prompt text>
[<|tool>declaration:toolname{params...}<tool|>]                # one per tool
[<|tool>declaration:toolname2{...}<tool|>]
<turn|>\n
<|turn>user\n
user message
<turn|>\n
<|turn>model\n                                               # generation starts here
```

### Assistant Tool Call Turn

```
<|turn>assistant\n
<|tool_call>call:toolname{json_args}<tool_call|>
<turn|>\n
```

### Tool Result Turn

```
<|turn>tool\n
<|tool_response>response:toolname{key:value}<tool_response|>
<turn|>\n
```

## Model Response Format

From `response_schema.x-regex` in tokenizer_config.json:

```
(\<\|channel\>thought\n(?P<thinking>.*?)\<channel\|\>)?
(?P<content>(?:(?!\<\|tool_call\>)(?!\<turn\|\>).)+)?
(?P<tool_calls>\<\|tool_call\>.*\<tool_call\|\>)?
(?:\<turn\|\>)?
```

In order:
1. **Thinking block** (optional): `<|channel>thought\n<reasoning><channel|>`
2. **Content** (optional): any text that is NOT `<|tool_call>` or `<turn|>`
3. **Tool call** (optional): `<|tool_call>call:name{json_args}<tool_call|>`
4. **Turn end** (optional): `<turn|>`

### Examples

```
# Text only
Sure, I can help you!<turn|>

# With thinking
<|channel>thought
The user wants to list files in their project.
<channel|>Here are the files I found:<turn|>

# With tool call (no thinking)
Let me check the project structure:<|tool_call>call:list_files{"path":"."}<tool_call|><turn|>

# Full: thinking + tool call
<|channel>thought
I should use read_file to examine the SPEC.
<channel|>Here's what I found in the spec:<|tool_call>call:read_file{"path":"sandbox/todo-app/SPEC.md"}<tool_call|><turn|>
```

## Tool Call Format

```
<|tool_call>call:tool_name{key1:value1,key2:value2}<tool_call|>
```

- Starts with `<|tool_call>` (id 48)
- Contains `call:` followed by the tool name
- Arguments are JSON object: `{"key": "value", ...}` (curly braces)
- Ends with `<tool_call|>` (id 49)

### Argument value types

- Strings: `key:value` or `key:string_value`
- Numbers: `key:42`
- Booleans: `key:true`
- Nested objects: `key:{subkey:value}`
- Arrays: `key:[item1,item2]`

Strings are NOT quoted — they're bare. Complex values like paths with special chars may still be bare.

## Tool Declaration Format

```
<|tool>declaration:toolname{description:<|"|>desc text<|"|>,parameters:{
  properties:{
    paramname:{
      description:<|"|>param desc<|"|>,
      type:<|"|>STRING<|"|>
    }
  },
  required:[<|"|>paramname<|"|>],
  type:<|"|>OBJECT<|"|>
}}<tool|>
```

- `<|"|>` (id 52) is used to delimit string values
- Keys are bare, not quoted
- Types are uppercase: `STRING`, `OBJECT`, `ARRAY`, `BOOLEAN`, `NUMBER`

## Tool Response Format

```
<|tool_response>response:toolname{key:value,...}<tool_response|>
```

- For simple values: `response:toolname{value:result_string}`
- For complex values: `response:toolname{key1:value1,key2:value2}`

## Thinking/Channel Tags

The `<|channel>` tag is used for the thinking block:
- `<|channel>thought\n` — starts the thinking section (the word "thought" after the tag is literal)
- `<channel|>` — ends the thinking section
- Everything between is the model's reasoning

## System Prompt

The system prompt can contain `<|think|>` if thinking is enabled for the model. This token at the start of the system turn configures the model to output reasoning in channel tags.

## Stream Processing Rules

When streaming the model output, apply in this order:

1. **Accumulate** chunks into a buffer (`draftAssistantText`)
2. **Strip thinking**: `<|channel>thought\n...<channel|>` → extract reasoning, remove
3. **Strip tool calls**: `<|tool_call>...<tool_call|>` → remove from content display
4. **Strip turn markers**: `<turn|>`, `<|turn>` → remove
5. **Strip stray tags**: `<|channel>`, `<channel|>`, `<|tool>`, `<tool|>`, `<|"|>`, `<|think|>`, etc.
6. **Normalize whitespace**: remove excessive newlines

## Key Differences from Previous Gemma Versions

- **Not** `<|channel|>thought` (both sides pipe) — it's `<|channel>thought\n` (pipe only on left start, pipe only on right end)
- **Not** `call:name\nplaintext_args` — it's `call:name{json_args}` with curly braces
- Tool call format uses JSON objects for arguments, not newline-separated plaintext
- `<turn|>` is both the turn end marker AND an EOS token (id 106)
- `<|tool_response>` token (id 50) is ALSO an EOS token — model stops generating after a tool response
- `<|"|>` (id 52) is used as string delimiter in tool declarations (like escaped quotes)

## Performance Notes

- 4-bit quantized: ~5.2 GB on disk, ~4 GB weights in memory
- KV cache: ~0.75 GB at 64K context (Q4)
- 128K max context length
- 42 layers, 8 attention heads, 2 KV heads
- Sliding window: layers alternate between sliding (512) and full attention (6 full-attention layers total)
- Recommended sampling: temp=1.0, top_k=64, top_p=0.95
- 262144 vocab size
