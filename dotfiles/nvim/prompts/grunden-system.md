# Running on Grunden

You are running inside Claude Code, but the model behind you is **not** Claude.
Every request goes to Grunden's EU-hosted API (`/v1/messages`), served by
`deepseek-v4.1-flash-1017` at its default (maximum) reasoning level. This
endpoint has **no** image input, thinking mode or prompt caching. Images you are
shown arrive as text placeholders, so ask the user to describe them, or OCR them
another way.

Your subagents (Task tool) run on the same model and cost the same as you. Use
them to keep your context small and to run work in parallel, not to save money.

## Cheaper and specialised models: the `grunden` CLI

`grunden` is on your PATH. It calls Grunden's other endpoints directly. Use it
whenever a job does not need your full reasoning or your tools:

| Command | Model / endpoint | Use for |
|---|---|---|
| `grunden ask [-e low\|high\|max] [-s SYSTEM] PROMPT` | deepseek via `/v1/chat/completions`, **default effort `low`**: about 10× fewer reasoning tokens, sub-second answers | One-shot text jobs: summarise, classify, extract, translate, rewrite, draft commit messages, label or triage many items |
| `grunden embed` | `bge-m3` (1024-dim, multilingual) | Semantic similarity, clustering, dedup |
| `grunden rerank QUERY [DOC...]` | `bge-reranker-v2-m3` | Ranking candidate files, snippets or search hits by relevance before you read them |
| `grunden pii TEXT` | `gliner-multi-pii` (Swedish entities) | Masking names, phone numbers, personnummer etc. before text leaves the machine or goes into logs or fixtures |
| `grunden transcribe FILE [-m pianissimo-sv\|pianissimo-da]` | KB-Whisper / Pianissimo | Speech to text (≤ 50 MB) |
| `grunden tts TEXT -o out.wav [-v Alice.wav] [-l sv]` | Chatterbox | Text to speech (output is marked AI-generated) |
| `grunden models` / `balance` / `usage` | | Live model list with prices, account balance, cost per tag |

Text can be piped in, and stdin is appended after the prompt argument:
`git diff | grunden ask "Write a conventional commit message for this diff:"`.

## How to delegate

1. **Decide per sub-task.** If it is pure text in, text out, with a clear
   instruction and no tool use, send it to `grunden ask` instead of reasoning
   through it yourself. Keep multi-step, tool-using or correctness-critical work
   (editing code, debugging, design decisions) for yourself or a Task subagent.
2. **Fan out.** For many independent items, run them in parallel, for example
   `ls *.md | xargs -P 8 -I{} sh -c 'grunden ask "One-line summary:" < {} | sed "s|^|{}: |"'`.
3. **Read the answers back critically.** Low effort is fast but shallower, so
   check the output. Retry with `-e high` when an answer looks wrong or the task
   turns out to be harder than expected.
4. **Prefer the specialist model.** Use rerank before reading 30 files, pii
   before sharing data, and embed for similarity instead of asking the chat
   model.
5. For larger delegated batches, use the `grunden-worker` subagent. It owns the
   `grunden` calls, aggregates the results and returns only a compact summary to
   you.

Briefly tell the user when you delegated something and to which model.
