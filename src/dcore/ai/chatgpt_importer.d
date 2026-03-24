module dcore.ai.chatgpt_importer;

import std.stdio;
import std.string;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.conv;
import std.json;
import std.datetime;
import std.exception;
import std.typecons;
import std.uuid;
import core.time;

import dlangui.core.logger;
import dcore.ai.ai_backend;

/**
 * ImportedChatMessage - Normalized message from ChatGPT export
 */
struct ImportedChatMessage {
    string id;
    AIMessage.Role role;
    string content;
    DateTime timestamp;
    string parentId;
    string[] childrenIds;
    JSONValue metadata;
    bool isLeaf;
    bool isRoot;
}

/**
 * ImportedChatThread - Normalized thread from ChatGPT export
 */
struct ImportedChatThread {
    string id;
    string title;
    string sourcePath;
    DateTime createdAt;
    DateTime updatedAt;
    ImportedChatMessage[] messagesLinear;
    ImportedChatMessage[string] messagesById;
    string rootMessageId;
    JSONValue rawMetadata;
}

/**
 * ImportSummary - Result summary for one import operation
 */
struct ImportSummary {
    size_t totalConversations;
    size_t importedConversations;
    size_t skippedConversations;
    size_t totalMessages;
    string[] warnings;
    string[] errors;
}

/**
 * ChatGPTImportResult - Full import result payload
 */
struct ChatGPTImportResult {
    ImportedChatThread[] threads;
    ImportSummary summary;
}

/**
 * ChatGPTImporter - Converts ChatGPT export JSON into normalized chat threads
 *
 * Supports:
 * - ChatGPT export list files (array of conversations)
 * - Single conversation objects
 * - Conversation mapping trees with parent/child links
 * - Message role/content normalization
 */
class ChatGPTImporter {
    private enum string DEFAULT_TITLE = "Imported ChatGPT Conversation";
    private enum string SOURCE_NAME = "chatgpt_export";

    /**
     * Import from file path.
     */
    ChatGPTImportResult importFromFile(string filePath) {
        ChatGPTImportResult result;
        result.summary = ImportSummary(0, 0, 0, 0, [], []);

        if (filePath.empty) {
            result.summary.errors ~= "Import path is empty.";
            return result;
        }

        if (!exists(filePath)) {
            result.summary.errors ~= "Import file not found: " ~ filePath;
            return result;
        }

        if (!isFile(filePath)) {
            result.summary.errors ~= "Import path is not a file: " ~ filePath;
            return result;
        }

        string content;
        try {
            content = readText(filePath);
        } catch (Exception e) {
            result.summary.errors ~= "Failed to read file: " ~ e.msg;
            return result;
        }

        auto parsed = importFromJson(content, filePath);
        return parsed;
    }

    /**
     * Import from JSON text.
     */
    ChatGPTImportResult importFromJson(string jsonText, string sourcePath = "") {
        ChatGPTImportResult result;
        result.summary = ImportSummary(0, 0, 0, 0, [], []);

        if (jsonText.strip.empty) {
            result.summary.errors ~= "Input JSON is empty.";
            return result;
        }

        JSONValue root;
        try {
            root = parseJSON(jsonText);
        } catch (Exception e) {
            result.summary.errors ~= "Failed to parse JSON: " ~ e.msg;
            return result;
        }

        try {
            switch (root.type) {
                case JSONType.array:
                    result.summary.totalConversations = root.array.length;
                    foreach (idx, convJson; root.array) {
                        auto maybeThread = parseConversation(convJson, sourcePath, idx);
                        if (maybeThread.isNull) {
                            result.summary.skippedConversations++;
                            continue;
                        }

                        auto thread = maybeThread.get;
                        result.threads ~= thread;
                        result.summary.importedConversations++;
                        result.summary.totalMessages += thread.messagesLinear.length;
                    }
                    break;

                case JSONType.object:
                    result.summary.totalConversations = 1;
                    auto maybeThread = parseConversation(root, sourcePath, 0);
                    if (maybeThread.isNull) {
                        result.summary.skippedConversations = 1;
                    } else {
                        auto thread = maybeThread.get;
                        result.threads ~= thread;
                        result.summary.importedConversations = 1;
                        result.summary.totalMessages = thread.messagesLinear.length;
                    }
                    break;

                default:
                    result.summary.errors ~= "Unsupported JSON root type for ChatGPT import.";
                    break;
            }
        } catch (Exception e) {
            result.summary.errors ~= "Import processing failed: " ~ e.msg;
        }

        if (result.summary.importedConversations == 0 && result.summary.errors.empty) {
            result.summary.warnings ~= "No conversations were imported. Check export format.";
        }

        Log.i("ChatGPTImporter: Imported ",
              result.summary.importedConversations.to!string,
              " conversation(s), ",
              result.summary.totalMessages.to!string,
              " message(s).");

        return result;
    }

private:
    Nullable!ImportedChatThread parseConversation(JSONValue convJson, string sourcePath, size_t indexHint) {
        if (convJson.type != JSONType.object) {
            return Nullable!ImportedChatThread.init;
        }

        string title = DEFAULT_TITLE;
        if (auto pTitle = "title" in convJson) {
            auto t = safeGetString(*pTitle);
            if (!t.empty) title = t;
        }

        string conversationId;
        if (auto pId = "id" in convJson) {
            conversationId = safeGetString(*pId);
        }
        if (conversationId.empty) {
            conversationId = randomUUID().toString();
        }

        auto createdAt = extractConversationCreatedAt(convJson);
        auto updatedAt = extractConversationUpdatedAt(convJson, createdAt);

        ImportedChatThread thread;
        thread.id = conversationId;
        thread.title = title;
        thread.sourcePath = sourcePath;
        thread.createdAt = createdAt;
        thread.updatedAt = updatedAt;
        thread.rawMetadata = buildThreadMetadata(convJson, sourcePath, indexHint);

        JSONValue* mappingPtr = "mapping" in convJson;
        if (mappingPtr is null || mappingPtr.type != JSONType.object) {
            // Fallback: some exports may use "messages" as an array
            auto fallbackMessages = parseFallbackMessages(convJson);
            if (fallbackMessages.empty) {
                return Nullable!ImportedChatThread.init;
            }

            thread.messagesLinear = fallbackMessages;
            foreach (m; fallbackMessages) {
                thread.messagesById[m.id] = m;
            }
            thread.rootMessageId = fallbackMessages[0].id;
            return Nullable!ImportedChatThread(thread);
        }

        auto parsedNodes = parseMappingNodes(*mappingPtr);

        if (parsedNodes.empty) {
            return Nullable!ImportedChatThread.init;
        }

        // Find roots
        string[] roots;
        foreach (id, node; parsedNodes) {
            if (node.parentId.empty) {
                roots ~= id;
            }
        }

        // If no explicit root, choose earliest message
        string rootId;
        if (!roots.empty) {
            rootId = chooseBestRoot(roots, parsedNodes);
        } else {
            rootId = chooseEarliestNode(parsedNodes);
        }

        // Linearize DFS from root, then append disconnected nodes deterministically
        string[] order = linearizeFromRoot(rootId, parsedNodes);

        // Add disconnected nodes if any
        foreach (id; parsedNodes.keys.sort.array) {
            if (!order.canFind(id)) {
                order ~= id;
            }
        }

        ImportedChatMessage[] linear;
        foreach (id; order) {
            auto node = parsedNodes[id];
            linear ~= node;
        }

        if (linear.empty) {
            return Nullable!ImportedChatThread.init;
        }

        // Mark root/leaf flags
        for (size_t i = 0; i < linear.length; i++) {
            auto msg = linear[i];
            msg.isRoot = (msg.parentId.empty);
            msg.isLeaf = msg.childrenIds.empty;
            linear[i] = msg;
        }

        thread.messagesLinear = linear;
        foreach (m; linear) {
            thread.messagesById[m.id] = m;
        }
        thread.rootMessageId = rootId;

        // Keep thread timestamps sane
        if (thread.createdAt == DateTime.init || thread.createdAt.year <= 1971) {
            thread.createdAt = linear[0].timestamp;
        }
        if (thread.updatedAt == DateTime.init || thread.updatedAt.year <= 1971) {
            thread.updatedAt = linear[$ - 1].timestamp;
        }

        return Nullable!ImportedChatThread(thread);
    }

    ImportedChatMessage[string] parseMappingNodes(JSONValue mappingObj) {
        ImportedChatMessage[string] out_;

        foreach (key, nodeJson; mappingObj.object) {
            if (nodeJson.type != JSONType.object) continue;

            string nodeId = key;
            if (nodeId.empty) nodeId = randomUUID().toString();

            string parentId;
            if (auto pParent = "parent" in nodeJson) {
                parentId = safeGetString(*pParent);
            }

            string[] children;
            if (auto pChildren = "children" in nodeJson) {
                if (pChildren.type == JSONType.array) {
                    foreach (c; pChildren.array) {
                        auto cid = safeGetString(c);
                        if (!cid.empty) children ~= cid;
                    }
                }
            }

            JSONValue* pMessage = "message" in nodeJson;
            if (pMessage is null || pMessage.type != JSONType.object) {
                continue;
            }

            auto msg = parseMessageObject(nodeId, *pMessage, parentId, children);
            out_[nodeId] = msg;
        }

        return out_;
    }

    ImportedChatMessage parseMessageObject(
        string id,
        JSONValue messageObj,
        string parentId,
        string[] children
    ) {
        ImportedChatMessage msg;
        msg.id = id;
        msg.parentId = parentId;
        msg.childrenIds = children;
        msg.role = AIMessage.Role.User;
        msg.timestamp = cast(DateTime)Clock.currTime();
        msg.metadata = JSONValue.emptyObject;
        msg.isLeaf = children.empty;
        msg.isRoot = parentId.empty;

        // role
        if (auto pAuthor = "author" in messageObj) {
            if (pAuthor.type == JSONType.object) {
                if (auto pRole = "role" in pAuthor.object) {
                    msg.role = parseRole(safeGetString(*pRole));
                }
            }
        }

        // timestamps
        if (auto pCreate = "create_time" in messageObj) {
            msg.timestamp = parseTimestamp(*pCreate, msg.timestamp);
        } else if (auto pUpdate = "update_time" in messageObj) {
            msg.timestamp = parseTimestamp(*pUpdate, msg.timestamp);
        }

        // content
        if (auto pContent = "content" in messageObj) {
            msg.content = extractMessageContent(*pContent);
        }

        if (msg.content.empty) {
            // Keep placeholder so structure isn't lost
            msg.content = "";
        }

        // metadata passthrough
        JSONValue md = JSONValue.emptyObject;
        if (auto pStatus = "status" in messageObj) md["status"] = *pStatus;
        if (auto pWeight = "weight" in messageObj) md["weight"] = *pWeight;
        if (auto pRecipient = "recipient" in messageObj) md["recipient"] = *pRecipient;
        if (auto pChannel = "channel" in messageObj) md["channel"] = *pChannel;
        if (auto pMeta = "metadata" in messageObj) md["message_metadata"] = *pMeta;
        md["source"] = SOURCE_NAME;
        msg.metadata = md;

        return msg;
    }

    ImportedChatMessage[] parseFallbackMessages(JSONValue convJson) {
        ImportedChatMessage[] out_;
        JSONValue* pMessages = "messages" in convJson;
        if (pMessages is null || pMessages.type != JSONType.array) return out_;

        ImportedChatMessage prev;
        bool havePrev = false;

        foreach (idx, mJson; pMessages.array) {
            if (mJson.type != JSONType.object) continue;

            ImportedChatMessage m;
            m.id = "msg_" ~ idx.to!string ~ "_" ~ randomUUID().toString()[0 .. 8];
            m.role = parseRole(safeGetString(mJson, "role", "user"));
            m.content = safeGetString(mJson, "content", "");
            m.timestamp = parseTimestamp(safeGet(mJson, "timestamp"), cast(DateTime)Clock.currTime());
            m.metadata = JSONValue.emptyObject;
            m.metadata["source"] = SOURCE_NAME;
            m.childrenIds = [];
            m.parentId = havePrev ? prev.id : "";
            m.isRoot = !havePrev;
            m.isLeaf = true;

            if (havePrev) {
                auto last = out_[$ - 1];
                last.childrenIds ~= m.id;
                last.isLeaf = false;
                out_[$ - 1] = last;
            }

            out_ ~= m;
            prev = m;
            havePrev = true;
        }

        return out_;
    }

    string[] linearizeFromRoot(string rootId, ImportedChatMessage[string] nodes) {
        string[] out_;
        if (rootId.empty || rootId !in nodes) return out_;

        bool[string] visited;
        void dfs(string id) {
            if (id.empty || id !in nodes) return;
            if (id in visited) return;
            visited[id] = true;

            out_ ~= id;

            auto node = nodes[id];
            auto sortedChildren = node.childrenIds.dup.sort.array;
            foreach (cid; sortedChildren) {
                dfs(cid);
            }
        }

        dfs(rootId);
        return out_;
    }

    string chooseBestRoot(string[] roots, ImportedChatMessage[string] nodes) {
        if (roots.length == 1) return roots[0];

        auto sorted = roots.dup.sort!((a, b) {
            auto ta = (a in nodes) ? nodes[a].timestamp : cast(DateTime)Clock.currTime();
            auto tb = (b in nodes) ? nodes[b].timestamp : cast(DateTime)Clock.currTime();
            if (ta == tb) return a < b;
            return ta < tb;
        }).array;

        return sorted[0];
    }

    string chooseEarliestNode(ImportedChatMessage[string] nodes) {
        if (nodes.empty) return "";
        auto keys = nodes.keys.array;
        auto sorted = keys.sort!((a, b) {
            auto ta = nodes[a].timestamp;
            auto tb = nodes[b].timestamp;
            if (ta == tb) return a < b;
            return ta < tb;
        }).array;
        return sorted[0];
    }

    DateTime extractConversationCreatedAt(JSONValue convJson) {
        auto now = cast(DateTime)Clock.currTime();
        if (auto pCreate = "create_time" in convJson) return parseTimestamp(*pCreate, now);
        if (auto pCreate2 = "created_at" in convJson) return parseTimestamp(*pCreate2, now);
        return now;
    }

    DateTime extractConversationUpdatedAt(JSONValue convJson, DateTime fallback) {
        if (auto pUpdate = "update_time" in convJson) return parseTimestamp(*pUpdate, fallback);
        if (auto pUpdate2 = "updated_at" in convJson) return parseTimestamp(*pUpdate2, fallback);
        return fallback;
    }

    JSONValue buildThreadMetadata(JSONValue convJson, string sourcePath, size_t indexHint) {
        JSONValue md = JSONValue.emptyObject;
        md["source"] = SOURCE_NAME;
        md["source_path"] = sourcePath;
        md["index_hint"] = cast(long) indexHint;

        if (auto pModeration = "moderation_results" in convJson) md["moderation_results"] = *pModeration;
        if (auto pPluginIds = "plugin_ids" in convJson) md["plugin_ids"] = *pPluginIds;
        if (auto pConvTemplateId = "conversation_template_id" in convJson) md["conversation_template_id"] = *pConvTemplateId;
        if (auto pMeta = "metadata" in convJson) md["metadata"] = *pMeta;

        return md;
    }

    string extractMessageContent(JSONValue contentObj) {
        if (contentObj.type != JSONType.object) {
            return safeGetString(contentObj);
        }

        // Most ChatGPT exports: { content_type: "...", parts: [...] }
        if (auto pParts = "parts" in contentObj) {
            if (pParts.type == JSONType.array) {
                string[] parts;
                foreach (part; pParts.array) {
                    auto piece = safeGetString(part);
                    if (!piece.empty) parts ~= piece;
                }
                return parts.join("\n");
            }
        }

        // Fallbacks for alternative structures
        if (auto pText = "text" in contentObj) return safeGetString(*pText);
        if (auto pResult = "result" in contentObj) return safeGetString(*pResult);
        if (auto pData = "data" in contentObj) return safeGetString(*pData);

        return "";
    }

    AIMessage.Role parseRole(string roleText) {
        auto role = roleText.strip.toLower();

        switch (role) {
            case "system": return AIMessage.Role.System;
            case "assistant": return AIMessage.Role.Assistant;
            case "tool": return AIMessage.Role.Tool;
            case "user": return AIMessage.Role.User;
            default: return AIMessage.Role.User;
        }
    }

    DateTime parseTimestamp(JSONValue value, DateTime fallback) {
        if (value.type == JSONType.null_) return fallback;

        auto unixToDateTime = (long sec) {
            auto st = SysTime.fromUnixTime(sec);
            return cast(DateTime)st;
        };

        // Numeric unix seconds
        if (value.type == JSONType.integer) {
            return unixToDateTime(cast(long)value.integer);
        }
        if (value.type == JSONType.uinteger) {
            return unixToDateTime(cast(long)value.uinteger);
        }
        if (value.type == JSONType.float_) {
            return unixToDateTime(cast(long)value.floating);
        }

        // String: ISO or numeric
        if (value.type == JSONType.string) {
            auto s = value.str.strip;
            if (s.empty) return fallback;

            // Try numeric string
            try {
                auto sec = to!long(s);
                return unixToDateTime(sec);
            } catch (Exception) {}

            // Try ISO ext string
            try {
                return DateTime.fromISOExtString(s);
            } catch (Exception) {}

            return fallback;
        }

        return fallback;
    }

    JSONValue safeGet(JSONValue obj, string key) {
        if (obj.type != JSONType.object) return JSONValue.init;
        auto ptr = key in obj.object;
        return ptr is null ? JSONValue.init : *ptr;
    }

    string safeGetString(JSONValue obj, string key, string fallback = "") {
        if (obj.type != JSONType.object) return fallback;
        auto ptr = key in obj.object;
        if (ptr is null) return fallback;
        return safeGetString(*ptr, fallback);
    }

    string safeGetString(JSONValue value, string fallback = "") {
        switch (value.type) {
            case JSONType.string:
                return value.str;
            case JSONType.integer:
                return value.integer.to!string;
            case JSONType.uinteger:
                return value.uinteger.to!string;
            case JSONType.float_:
                return value.floating.to!string;
            case JSONType.true_:
                return "true";
            case JSONType.false_:
                return "false";
            case JSONType.null_:
                return fallback;
            default:
                return fallback;
        }
    }
}
