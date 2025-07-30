local Utils = require("avante.utils")

describe("Utils.fix_diff", function()
  it("should not break normal diff", function()
    local diff = [[------- SEARCH
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="p-6">
                    <div className="py-8 overflow-auto text-sm">
                        <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        <div className="text-center">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
=======
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="flex flex-col" style={{ maxHeight: '80vh' }}>
                    <div className="flex-1 overflow-y-auto p-6">
                        <div className="text-sm font-mono whitespace-pre-wrap">
                            <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        </div>
                        <div className="text-center mt-4">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                        <div ref={(el) => {
                            if (el) {
                                el.scrollIntoView({ behavior: 'smooth', block: 'end' });
                            }
                        }} />
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end p-4 border-t">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
+++++++ REPLACE
]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(diff, fixed_diff)
  end)

  it("should not break normal multiple diff", function()
    local diff = [[------- SEARCH
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="p-6">
                    <div className="py-8 overflow-auto text-sm">
                        <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        <div className="text-center">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
=======
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="flex flex-col" style={{ maxHeight: '80vh' }}>
                    <div className="flex-1 overflow-y-auto p-6">
                        <div className="text-sm font-mono whitespace-pre-wrap">
                            <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        </div>
                        <div className="text-center mt-4">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                        <div ref={(el) => {
                            if (el) {
                                el.scrollIntoView({ behavior: 'smooth', block: 'end' });
                            }
                        }} />
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end p-4 border-t">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
+++++++ REPLACE

------- SEARCH
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="p-6">
=======
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl aaa">
                <div className="p-12">
+++++++ REPLACE
]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(diff, fixed_diff)
  end)

  it("should fix duplicated REPLACE delimiters", function()
    local diff = [[------- SEARCH
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="p-6">
                    <div className="py-8 overflow-auto text-sm">
                        <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        <div className="text-center">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
------- REPLACE
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="flex flex-col" style={{ maxHeight: '80vh' }}>
                    <div className="flex-1 overflow-y-auto p-6">
                        <div className="text-sm font-mono whitespace-pre-wrap">
                            <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        </div>
                        <div className="text-center mt-4">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                        <div ref={(el) => {
                            if (el) {
                                el.scrollIntoView({ behavior: 'smooth', block: 'end' });
                            }
                        }} />
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end p-4 border-t">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
------- REPLACE
]]

    local expected_diff = [[------- SEARCH
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="p-6">
                    <div className="py-8 overflow-auto text-sm">
                        <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        <div className="text-center">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
=======
            <Modal isOpen={showLogs} onClose={() => setShowLogs(false)} title="Project PRD Logs" size="xl">
                <div className="flex flex-col" style={{ maxHeight: '80vh' }}>
                    <div className="flex-1 overflow-y-auto p-6">
                        <div className="text-sm font-mono whitespace-pre-wrap">
                            <ReactMarkdown remarkPlugins={[remarkGfm]}>{logs.split('\n').join('\n\n')}</ReactMarkdown>
                        </div>
                        <div className="text-center mt-4">{logsLoading && <ScaleLoader color="#555" width={3} height={10} speedMultiplier={2.3} />}</div>
                        <div ref={(el) => {
                            if (el) {
                                el.scrollIntoView({ behavior: 'smooth', block: 'end' });
                            }
                        }} />
                    </div>
                </div>
                {logs.length > 0 && (
                    <div className="flex justify-end p-4 border-t">
                        <button
                            onClick={() => setShowLogs(false)}
                            className="bg-japanese-chigusa-600 text-white px-4 py-2 hover:bg-japanese-chigusa-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                        >
                            Close
                        </button>
                    </div>
                )}
            </Modal>
+++++++ REPLACE
]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(expected_diff, fixed_diff)
  end)

  it("should fix the delimiter is on the same line as the content", function()
    local diff = [[-------     // Fetch initial stages when project changes
  useEffect(() => {
    if (!subscribedProject) return;

    const fetchStages = async () => {
      try {
        const response = await fetch(`/api/projects/${subscribedProject}/stages`);
        if (response.ok) {
          const stagesData = await response.json();
          setStages(stagesData);
        }
      } catch (error) {
        console.error('Failed to fetch stages:', error);
      }
    };

    fetchStages();
  }, [subscribedProject, forceUpdateCounter]);
=======     // Fetch initial stages when project changes
  useEffect(() => {
    if (!subscribedProject) return;

    const fetchStages = async () => {
      try {
        // Use the correct API endpoint for stages by project UUID
        const response = await fetch(`/api/stages?project_uuid=${subscribedProject}`);
        if (response.ok) {
          const stagesData = await response.json();
          setStages(stagesData);
        }
      } catch (error) {
        console.error('Failed to fetch stages:', error);
      }
    };

    fetchStages();
  }, [subscribedProject, forceUpdateCounter]);
+++++++ REPLACE
]]

    local expected_diff = [[------- SEARCH
   // Fetch initial stages when project changes
  useEffect(() => {
    if (!subscribedProject) return;

    const fetchStages = async () => {
      try {
        const response = await fetch(`/api/projects/${subscribedProject}/stages`);
        if (response.ok) {
          const stagesData = await response.json();
          setStages(stagesData);
        }
      } catch (error) {
        console.error('Failed to fetch stages:', error);
      }
    };

    fetchStages();
  }, [subscribedProject, forceUpdateCounter]);
=======
   // Fetch initial stages when project changes
  useEffect(() => {
    if (!subscribedProject) return;

    const fetchStages = async () => {
      try {
        // Use the correct API endpoint for stages by project UUID
        const response = await fetch(`/api/stages?project_uuid=${subscribedProject}`);
        if (response.ok) {
          const stagesData = await response.json();
          setStages(stagesData);
        }
      } catch (error) {
        console.error('Failed to fetch stages:', error);
      }
    };

    fetchStages();
  }, [subscribedProject, forceUpdateCounter]);
+++++++ REPLACE
]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(expected_diff, fixed_diff)
  end)

  it("should fix unified diff", function()
    local diff = [[--- lua/avante/sidebar.lua
+++ lua/avante/sidebar.lua
@@ -3099,7 +3099,7 @@
 function Sidebar:create_todos_container()
   local history = Path.history.load(self.code.bufnr)
   if not history or not history.todos or #history.todos == 0 then
-    if self.containers.todos then self.containers.todos:unmount() end
+    if self.containers.todos and Utils.is_valid_container(self.containers.todos) then self.containers.todos:unmount() end
     self.containers.todos = nil
     self:adjust_layout()
     return
@@ -3121,7 +3121,7 @@
     }),
     position = "bottom",
     size = {
-      height = 3,
+      height = math.min(3, math.max(1, vim.o.lines - 5)),
     },
   })
   self.containers.todos:mount()
@@ -3151,11 +3151,15 @@
   self:render_header(
     self.containers.todos.winid,
     todos_buf,
-    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
+    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
     Highlights.SUBTITLE,
     Highlights.REVERSED_SUBTITLE
   )
-  self:adjust_layout()
+
+  local ok, err = pcall(function()
+    self:adjust_layout()
+  end)
+  if not ok then Utils.debug("Failed to adjust layout after todos creation:", err) end
 end

 function Sidebar:adjust_layout()
]]

    local expected_diff = [[------- SEARCH
function Sidebar:create_todos_container()
  local history = Path.history.load(self.code.bufnr)
  if not history or not history.todos or #history.todos == 0 then
    if self.containers.todos then self.containers.todos:unmount() end
    self.containers.todos = nil
    self:adjust_layout()
    return
=======
function Sidebar:create_todos_container()
  local history = Path.history.load(self.code.bufnr)
  if not history or not history.todos or #history.todos == 0 then
    if self.containers.todos and Utils.is_valid_container(self.containers.todos) then self.containers.todos:unmount() end
    self.containers.todos = nil
    self:adjust_layout()
    return
+++++++ REPLACE

------- SEARCH
}),
    position = "bottom",
    size = {
      height = 3,
    },
  })
  self.containers.todos:mount()
=======
}),
    position = "bottom",
    size = {
      height = math.min(3, math.max(1, vim.o.lines - 5)),
    },
  })
  self.containers.todos:mount()
+++++++ REPLACE

------- SEARCH
self:render_header(
    self.containers.todos.winid,
    todos_buf,
    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )
  self:adjust_layout()
end
function Sidebar:adjust_layout()
=======
self:render_header(
    self.containers.todos.winid,
    todos_buf,
    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )

  local ok, err = pcall(function()
    self:adjust_layout()
  end)
  if not ok then Utils.debug("Failed to adjust layout after todos creation:", err) end
end
function Sidebar:adjust_layout()
+++++++ REPLACE]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(expected_diff, fixed_diff)
  end)

  it("should fix unified diff 2", function()
    local diff = [[
@@ -3099,7 +3099,7 @@
 function Sidebar:create_todos_container()
   local history = Path.history.load(self.code.bufnr)
   if not history or not history.todos or #history.todos == 0 then
-    if self.containers.todos then self.containers.todos:unmount() end
+    if self.containers.todos and Utils.is_valid_container(self.containers.todos) then self.containers.todos:unmount() end
     self.containers.todos = nil
     self:adjust_layout()
     return
@@ -3121,7 +3121,7 @@
     }),
     position = "bottom",
     size = {
-      height = 3,
+      height = math.min(3, math.max(1, vim.o.lines - 5)),
     },
   })
   self.containers.todos:mount()
@@ -3151,11 +3151,15 @@
   self:render_header(
     self.containers.todos.winid,
     todos_buf,
-    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
+    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
     Highlights.SUBTITLE,
     Highlights.REVERSED_SUBTITLE
   )
-  self:adjust_layout()
+
+  local ok, err = pcall(function()
+    self:adjust_layout()
+  end)
+  if not ok then Utils.debug("Failed to adjust layout after todos creation:", err) end
 end

 function Sidebar:adjust_layout()
]]
    local expected_diff = [[------- SEARCH
function Sidebar:create_todos_container()
  local history = Path.history.load(self.code.bufnr)
  if not history or not history.todos or #history.todos == 0 then
    if self.containers.todos then self.containers.todos:unmount() end
    self.containers.todos = nil
    self:adjust_layout()
    return
=======
function Sidebar:create_todos_container()
  local history = Path.history.load(self.code.bufnr)
  if not history or not history.todos or #history.todos == 0 then
    if self.containers.todos and Utils.is_valid_container(self.containers.todos) then self.containers.todos:unmount() end
    self.containers.todos = nil
    self:adjust_layout()
    return
+++++++ REPLACE

------- SEARCH
}),
    position = "bottom",
    size = {
      height = 3,
    },
  })
  self.containers.todos:mount()
=======
}),
    position = "bottom",
    size = {
      height = math.min(3, math.max(1, vim.o.lines - 5)),
    },
  })
  self.containers.todos:mount()
+++++++ REPLACE

------- SEARCH
self:render_header(
    self.containers.todos.winid,
    todos_buf,
    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )
  self:adjust_layout()
end
function Sidebar:adjust_layout()
=======
self:render_header(
    self.containers.todos.winid,
    todos_buf,
    Utils.icon(" ") .. "Todos" .. " (" .. done_count .. "/" .. total_count .. ")",
    Highlights.SUBTITLE,
    Highlights.REVERSED_SUBTITLE
  )

  local ok, err = pcall(function()
    self:adjust_layout()
  end)
  if not ok then Utils.debug("Failed to adjust layout after todos creation:", err) end
end
function Sidebar:adjust_layout()
+++++++ REPLACE]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(expected_diff, fixed_diff)
  end)

  it("should fix duplicated replace blocks", function()
    local diff = [[------- SEARCH
    useEffect(() => {
        if (!isExpanded || !textContentRef.current) {
            setShowFixedCollapseButton(false);
            return;
        }

        const observer = new IntersectionObserver(
            ([entry]) => {
                setShowFixedCollapseButton(!entry.isIntersecting);
            },
            {
                root: null,
                rootMargin: '0px',
                threshold: 1.0,
            }
        );

        const collapseButton = collapseButtonRef.current;
        if (collapseButton) {
            observer.observe(collapseButton);
        }

        return () => {
            if (collapseButton) {
                observer.unobserve(collapseButton);
            }
        };
    }, [isExpanded, textContentRef.current]);
=======
    useEffect(() => {
        if (!isExpanded || !textContentRef.current) {
            setShowFixedCollapseButton(false);
            return;
        }

        // Check initial visibility of the collapse button
        const checkInitialVisibility = () => {
            const collapseButton = collapseButtonRef.current;
            if (collapseButton) {
                const rect = collapseButton.getBoundingClientRect();
                const isVisible = rect.top >= 0 && rect.bottom <= window.innerHeight;
                setShowFixedCollapseButton(!isVisible);
            }
        };

        // Small delay to ensure DOM is updated after expansion
        const timeoutId = setTimeout(checkInitialVisibility, 100);

        const observer = new IntersectionObserver(
            ([entry]) => {
                setShowFixedCollapseButton(!entry.isIntersecting);
            },
            {
                root: null,
                rootMargin: '0px',
                threshold: [0, 1.0], // Check both when it starts to leave and when fully visible
            }
        );

        const collapseButton = collapseButtonRef.current;
        if (collapseButton) {
            observer.observe(collapseButton);
        }

        return () => {
            clearTimeout(timeoutId);
            if (collapseButton) {
                observer.unobserve(collapseButton);
            }
        };
    }, [isExpanded, textContentRef.current]);
=======
    useEffect(() => {
        if (!isExpanded || !textContentRef.current) {
            setShowFixedCollapseButton(false);
            return;
        }

        // Check initial visibility of the collapse button
        const checkInitialVisibility = () => {
            const collapseButton = collapseButtonRef.current;
            if (collapseButton) {
                const rect = collapseButton.getBoundingClientRect();
                const isVisible = rect.top >= 0 && rect.bottom <= window.innerHeight;
                setShowFixedCollapseButton(!isVisible);
            }
        };

        // Small delay to ensure DOM is updated after expansion
        const timeoutId = setTimeout(checkInitialVisibility, 100);

        const observer = new IntersectionObserver(
            ([entry]) => {
                setShowFixedCollapseButton(!entry.isIntersecting);
            },
            {
                root: null,
                rootMargin: '0px',
                threshold: [0, 1.0], // Check both when it starts to leave and when fully visible
            }
        );

        const collapseButton = collapseButtonRef.current;
        if (collapseButton) {
            observer.observe(collapseButton);
        }

        return () => {
            clearTimeout(timeoutId);
            if (collapseButton) {
                observer.unobserve(collapseButton);
            }
        };
    }, [isExpanded, textContentRef.current]);
+++++++ REPLACE
]]

    local expected_diff = [[------- SEARCH
    useEffect(() => {
        if (!isExpanded || !textContentRef.current) {
            setShowFixedCollapseButton(false);
            return;
        }

        const observer = new IntersectionObserver(
            ([entry]) => {
                setShowFixedCollapseButton(!entry.isIntersecting);
            },
            {
                root: null,
                rootMargin: '0px',
                threshold: 1.0,
            }
        );

        const collapseButton = collapseButtonRef.current;
        if (collapseButton) {
            observer.observe(collapseButton);
        }

        return () => {
            if (collapseButton) {
                observer.unobserve(collapseButton);
            }
        };
    }, [isExpanded, textContentRef.current]);
=======
    useEffect(() => {
        if (!isExpanded || !textContentRef.current) {
            setShowFixedCollapseButton(false);
            return;
        }

        // Check initial visibility of the collapse button
        const checkInitialVisibility = () => {
            const collapseButton = collapseButtonRef.current;
            if (collapseButton) {
                const rect = collapseButton.getBoundingClientRect();
                const isVisible = rect.top >= 0 && rect.bottom <= window.innerHeight;
                setShowFixedCollapseButton(!isVisible);
            }
        };

        // Small delay to ensure DOM is updated after expansion
        const timeoutId = setTimeout(checkInitialVisibility, 100);

        const observer = new IntersectionObserver(
            ([entry]) => {
                setShowFixedCollapseButton(!entry.isIntersecting);
            },
            {
                root: null,
                rootMargin: '0px',
                threshold: [0, 1.0], // Check both when it starts to leave and when fully visible
            }
        );

        const collapseButton = collapseButtonRef.current;
        if (collapseButton) {
            observer.observe(collapseButton);
        }

        return () => {
            clearTimeout(timeoutId);
            if (collapseButton) {
                observer.unobserve(collapseButton);
            }
        };
    }, [isExpanded, textContentRef.current]);
+++++++ REPLACE]]

    local fixed_diff = Utils.fix_diff(diff)
    assert.equals(expected_diff, fixed_diff)
  end)
end)
