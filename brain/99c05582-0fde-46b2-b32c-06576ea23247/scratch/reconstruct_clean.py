import json

log_path = "/Users/rionita_work/.gemini/antigravity-ide/brain/99c05582-0fde-46b2-b32c-06576ea23247/.system_generated/logs/transcript.jsonl"
target_file = "/Users/rionita_work/im-liti/frontend/lib/screens/licitacion_detail_screen.dart"

with open(target_file, "r") as f:
    content = f.read()

edits = []

with open(log_path, 'r') as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get("status") != "DONE":
                continue
            step = data.get("step_index", 0)
            
            if "tool_calls" in data:
                for tc in data["tool_calls"]:
                    if tc["name"] in ("replace_file_content", "multi_replace_file_content"):
                        args = tc["args"]
                        if isinstance(args, str):
                            args = json.loads(args)
                        
                        tf = args.get("TargetFile", "")
                        if "licitacion_detail_screen.dart" in tf:
                            edits.append((step, tc["name"], args))
        except Exception as e:
            pass

print(f"Found {len(edits)} edits to replay.")
edits.sort(key=lambda x: x[0])

def clean_str(s):
    if not s:
        return s
    
    # Strip literal enclosing quotes if they got serialized into the string
    if len(s) >= 2 and s.startswith('"') and s.endswith('"'):
        try:
            s = json.loads(s)
        except:
            s = s[1:-1]
            
    # Unescape backslashes if present
    if "\\" in s:
        try:
            s = bytes(s, "utf-8").decode("unicode_escape")
        except Exception as e:
            # Fallback simple replacement
            s = s.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\'", "'").replace("\\\\", "\\")
            
    return s

for step, tool_name, args in edits:
    print(f"Replaying step {step} ({tool_name})...")
    if tool_name == "replace_file_content":
        target = clean_str(args.get("TargetContent"))
        replacement = clean_str(args.get("ReplacementContent"))
        if not target or not replacement:
            print(f"Skipping step {step} due to missing args.")
            continue
        if target not in content:
            normalized_target = target.replace("\r\n", "\n")
            if normalized_target in content:
                content = content.replace(normalized_target, replacement, 1)
            else:
                print(f"WARNING: Target not found at step {step}!")
                print("Target (repr):", repr(target[:100]) + "..." if len(target) > 100 else repr(target))
        else:
            content = content.replace(target, replacement, 1)
    elif tool_name == "multi_replace_file_content":
        chunks = args.get("ReplacementChunks", [])
        if isinstance(chunks, str):
            chunks = json.loads(chunks)
        for chunk in chunks:
            target = clean_str(chunk.get("TargetContent"))
            replacement = clean_str(chunk.get("ReplacementContent"))
            if not target or not replacement:
                continue
            if target not in content:
                normalized_target = target.replace("\r\n", "\n")
                if normalized_target in content:
                    content = content.replace(normalized_target, replacement, 1)
                else:
                    print(f"WARNING: Target not found in multi-replace chunk at step {step}!")
                    print("Target (repr):", repr(target[:100]) + "..." if len(target) > 100 else repr(target))
            else:
                content = content.replace(target, replacement, 1)

with open(target_file, "w") as f:
    f.write(content)

print(f"Reconstruction complete. Saved directly to {target_file}")
