**1. Prompt Canonicalization**
- Unclear how to handle minor formatting differences (e.g., whitespace, newline, Unicode normalization) that shouldn't affect cache keys. Is there a canonicalization spec or library to use?
- Which parameters must always be included in the cache key (e.g., model, temperature, user ID, system prompt, tool list)?
- How should non-string params (e.g., tool objects, complex configs) be serialized? Is the key generation deterministic and consistent across platforms?
- What about provider-specific quirks (e.g., OpenAI may have undocumented params that influence responses)?

**2. Cache Invalidation & Expiry**
- No concrete expiration or eviction policy is specified (e.g., TTL, LRU, size limit). How is stale cache data avoided?
- Should cache entries be invalidated on provider/model version changes, or only via manual purge?
- How to handle partial cache invalidation (e.g., per-user, per-model)?

**3. Streaming/Chunked Completions**
- The strategy mentions chunked/streaming results but does not specify if partials should be cached, or only complete responses. What if the client cancels a stream?
- How do we ensure cache consistency for streaming APIs where intermediate results may differ from the final output?

**4. Error Handling & Observability**
- What should happen if the cache backend fails or is slow (e.g., fallback to direct API call, log warning, raise error)?
- Is there a unified logging/metrics system for cache hits, misses, and errors?

**5. Pluggable Backends & Configuration**
- What are the requirements for backend interfaces (e.g., atomicity, concurrency, durability)?
- How does the user configure or swap backends? Is hot-reloading supported?
- Are there recommended defaults for local vs. production (e.g., file for dev, Redis for prod)?

**6. Privacy & Security**
- Prompt/result caching could leak sensitive info if not properly isolated in multi-tenant environments. Is per-user or per-namespace isolation supported?
- Is the cache encrypted at rest or in transit? Are access controls enforced?
- What about GDPR/right-to-erasure scenarios: can individual cached items be removed on request?

**7. Provider Updates & Model Drift**
- If a provider updates their model or changes API behaviour, how is stale or invalid cache recognized and purged?
- Is there a mechanism for automatic migration of cache entries?

**8. Integration with Existing Avante Features**
- How will cache interact with prompt logging/history? Can users distinguish between cache hits and new completions?
- How will this framework fit with Avante's provider abstraction—will each provider need custom hooks or is the logic fully generic?

