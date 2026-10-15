"""RetroAchievements Web API client (``/API/API_*.php`` with the user's Web API key).

Only the Web API is used; the Connect API (``dorequest.php``) belongs to emulators and the
offline proxy. Import from the modules (``client``, ``transport``, ``pacer``, ...): this package
imports nothing itself, so importing the pacer or the log redaction doesn't load
``http.client`` and ``ssl`` at start-up (.agents/device.md, "Start-up").
"""
