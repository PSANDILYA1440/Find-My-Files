"use strict";

const App = (() => {
    const nameCollator = new Intl.Collator(undefined, {
        numeric: true,
        sensitivity: "base"
    });
    const state = {
        currentLocation: null,
        backStack: [],
        forwardStack: [],
        searchQuery: "",
        viewMode: "list",
        sortBy: "name",
        selectedItemID: null
    };

    const elements = {};

    function initialize() {
        elements.sidebar = document.querySelector("#sidebar-locations");
        elements.searchInput = document.querySelector(
            '.search-box input[type="search"]'
        );
        elements.fileList = document.querySelector("#file-list");
        elements.browserMessage = document.querySelector("#browser-message");
        elements.pageEyebrow = document.querySelector("#page-eyebrow");
        elements.pageTitle = document.querySelector("#page-title");
        elements.pageSubtitle = document.querySelector("#page-subtitle");
        elements.emptyTitle = document.querySelector("#empty-title");
        elements.emptyDescription = document.querySelector("#empty-description");
        elements.statusText = document.querySelector("#status-text");
        elements.backButton = document.querySelector(
            '.navigation-controls button[aria-label="Back"]'
        );
        elements.forwardButton = document.querySelector(
            '.navigation-controls button[aria-label="Forward"]'
        );
        elements.viewButtons = document.querySelectorAll("[data-view]");
        elements.menuToggle = document.querySelector("#app-menu-toggle");
        elements.appMenu = document.querySelector("#app-menu");

        elements.backButton.addEventListener("click", goBack);
        elements.forwardButton.addEventListener("click", goForward);
        elements.viewButtons.forEach((button) => {
            button.addEventListener("click", () => setViewMode(button.dataset.view));
        });
        elements.menuToggle.addEventListener("click", toggleAppMenu);
        elements.appMenu.addEventListener("click", handleAppMenuClick);
        document.addEventListener("click", (event) => {
            if (!elements.appMenu.hidden
                && !elements.appMenu.contains(event.target)
                && !elements.menuToggle.contains(event.target)) {
                closeAppMenu();
            }
        });
        document.addEventListener("keydown", (event) => {
            if (event.key === "Escape" && !elements.appMenu.hidden) {
                closeAppMenu();
                elements.menuToggle.focus();
            }
            if ((event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === "r") {
                event.preventDefault();
                refreshCurrentLocation();
            }
        });
        elements.searchInput.addEventListener("input", () => {
            state.searchQuery = elements.searchInput.value.trim().toLocaleLowerCase();
            renderItems();
        });
        document.querySelector("#full-disk-access").addEventListener("click", () => {
            sendNative({ action: "requestFullDiskAccess" });
        });
        elements.fileList.addEventListener("click", (event) => {
            const item = event.target.closest("[data-item-id]");
            if (!item) return;
            state.selectedItemID = item.dataset.itemId;
            updateSelectedItem();
        });

        elements.fileList.addEventListener("dblclick", (event) => {
            const item = event.target.closest("[data-item-id]");
            if (!item) return;
            openItem(item);
        });

        elements.fileList.addEventListener("contextmenu", (event) => {
            const item = event.target.closest("[data-item-id]");
            if (!item) return;
            event.preventDefault();
            state.selectedItemID = item.dataset.itemId;
            updateSelectedItem();
            sendNative({
                action: "showContextMenu",
                itemId: item.dataset.itemId,
                x: event.clientX,
                y: event.clientY
            });
        });

        elements.fileList.addEventListener("keydown", (event) => {
            if (event.key !== "Enter" && event.key !== " ") return;
            const item = event.target.closest("[data-item-id]");
            if (!item) return;
            event.preventDefault();
            openItem(item);
        });

        sendNative({ action: "getSidebar" });
    }

    function openItem(item) {
        const isDirectory = item.dataset.directory === "true";
        const message = {
            action: isDirectory ? "listDirectory" : "openItem",
            itemId: item.dataset.itemId
        };
        if (isDirectory) {
            state.backStack.push(state.currentLocation);
            state.forwardStack = [];
            updateNavigationButtons();
        }
        if (!sendNative(message) && isDirectory) {
            state.backStack.pop();
            updateNavigationButtons();
        }
    }

    function openItemFromMenu(payload) {
        if (typeof payload?.itemID !== "string") return;
        const item = [...elements.fileList.querySelectorAll("[data-item-id]")]
            .find((row) => row.dataset.itemId === payload.itemID);
        if (item) openItem(item);
    }

    function setViewMode(mode) {
        if (mode !== "list" && mode !== "icons") return;
        state.viewMode = mode;
        elements.fileList.classList.toggle("icon-view", mode === "icons");
        document.querySelector(".file-browser").classList.toggle("icon-view", mode === "icons");
        elements.viewButtons.forEach((button) => {
            const selected = button.dataset.view === mode;
            button.classList.toggle("active", selected);
            button.setAttribute("aria-pressed", String(selected));
        });
        elements.appMenu.querySelectorAll("[data-menu-view]").forEach((button) => {
            const selected = button.dataset.menuView === mode;
            button.setAttribute("aria-pressed", String(selected));
            button.querySelector(".app-menu-check").hidden = !selected;
        });
    }

    function toggleAppMenu() {
        const shouldOpen = elements.appMenu.hidden;
        elements.appMenu.hidden = !shouldOpen;
        elements.menuToggle.setAttribute("aria-expanded", String(shouldOpen));
    }

    function closeAppMenu() {
        elements.appMenu.hidden = true;
        elements.menuToggle.setAttribute("aria-expanded", "false");
    }

    function handleAppMenuClick(event) {
        const viewButton = event.target.closest("[data-menu-view]");
        if (viewButton) {
            setViewMode(viewButton.dataset.menuView);
            closeAppMenu();
            elements.menuToggle.focus();
            return;
        }

        const sortButton = event.target.closest("[data-menu-sort]");
        if (sortButton) {
            state.sortBy = sortButton.dataset.menuSort;
            elements.appMenu.querySelectorAll("[data-menu-sort]").forEach((button) => {
                const selected = button === sortButton;
                button.setAttribute("aria-pressed", String(selected));
                button.querySelector(".app-menu-check").hidden = !selected;
            });
            renderItems();
            closeAppMenu();
            elements.menuToggle.focus();
            return;
        }

        const action = event.target.closest("[data-menu-action]")?.dataset.menuAction;
        if (action === "refresh") {
            refreshCurrentLocation();
        } else if (action === "full-disk-access") {
            sendNative({ action: "requestFullDiskAccess" });
        } else {
            return;
        }
        closeAppMenu();
        elements.menuToggle.focus();
    }

    function refreshCurrentLocation() {
        sendNative({ action: "refreshLocation" });
    }

    function updateSelectedItem() {
        elements.fileList.querySelectorAll("[data-item-id]").forEach((item) => {
            const selected = item.dataset.itemId === state.selectedItemID;
            item.classList.toggle("selected", selected);
            item.setAttribute("aria-selected", String(selected));
        });
    }

    function sendNative(message) {
        const bridge = window.webkit?.messageHandlers?.findMyFiles;
        if (!bridge) {
            showMessage("Native features unavailable", "Open this interface from Find My Files to access your files.");
            return false;
        }
        bridge.postMessage(message);
        return true;
    }

    function renderSidebar(groups) {
        elements.sidebar.replaceChildren();
        let homeButton = null;
        groups.forEach((group) => {
            const section = document.createElement("section");
            section.className = "sidebar-section";

            const heading = document.createElement("div");
            heading.className = "section-label";
            heading.textContent = group.title;
            section.append(heading);

            group.items.forEach((item) => {
                const button = document.createElement("button");
                button.className = "nav-item";
                button.dataset.locationId = item.id;
                button.setAttribute("aria-current", "false");
                if (item.id === "home") homeButton = button;

                const icon = document.createElement("span");
                icon.className = "location-icon";
                icon.setAttribute("aria-hidden", "true");
                icon.textContent = item.icon;
                const label = document.createElement("span");
                label.className = "location-label";
                label.textContent = item.name;
                button.append(icon, label);
                button.addEventListener("click", () => {
                    elements.sidebar.querySelectorAll(".nav-item").forEach((navItem) => {
                        const active = navItem === button;
                        navItem.classList.toggle("active", active);
                        navItem.setAttribute("aria-current", active ? "page" : "false");
                    });
                    state.backStack = [];
                    state.forwardStack = [];
                    sendNative({
                        action: "openLocation",
                        locationId: item.id
                    });
                });
                section.append(button);
            });

            elements.sidebar.append(section);
        });

        if (homeButton) {
            homeButton.classList.add("active");
            homeButton.setAttribute("aria-current", "page");
            sendNative({ action: "openLocation", locationId: "home" });
        }
    }

    function showLocation(location) {
        state.currentLocation = location;
        state.backStack = [];
        state.forwardStack = [];
        elements.pageEyebrow.textContent = location.section || "LOCATION";
        elements.pageTitle.textContent = location.title;
        elements.pageSubtitle.textContent = location.path || location.description || "";
        elements.statusText.textContent = location.error ? "Access unavailable" : location.path || "Ready";
        elements.searchInput.value = "";
        state.searchQuery = "";
        state.selectedItemID = null;
        renderItems();
        updateNavigationButtons();
    }

    function showDirectory(directory) {
        state.currentLocation = directory;
        elements.pageEyebrow.textContent = "FOLDER";
        elements.pageTitle.textContent = directory.title;
        elements.pageSubtitle.textContent = directory.path || "";
        elements.statusText.textContent = directory.error ? "Access unavailable" : directory.path || "Ready";
        state.selectedItemID = null;
        renderItems();
        updateNavigationButtons();
    }

    function renderItems() {
        elements.fileList.replaceChildren();
        const items = (state.currentLocation?.items || []).filter((item) =>
            item.name.toLocaleLowerCase().includes(state.searchQuery)
        ).sort(compareItems);

        items.forEach((item) => {
            const row = document.createElement("button");
            row.className = "file-row";
            row.type = "button";
            row.setAttribute("role", "listitem");
            row.dataset.itemId = item.id;
            row.dataset.directory = String(item.isDirectory);
            row.dataset.kind = item.kind || (item.isDirectory ? "folder" : "document");
            row.setAttribute("aria-selected", "false");

            const nameCell = document.createElement("span");
            nameCell.className = "file-name-cell";
            const icon = document.createElement("span");
            icon.className = "file-icon";
            icon.setAttribute("aria-hidden", "true");
            const fallbackIcon = document.createElement("span");
            fallbackIcon.className = "file-icon-fallback";
            fallbackIcon.textContent = iconGlyph(row.dataset.kind);
            icon.append(fallbackIcon);
            const iconData = state.currentLocation?.icons?.[item.iconID];
            if (typeof iconData === "string") {
                const image = document.createElement("img");
                image.className = "file-icon-image";
                image.alt = "";
                image.src = `data:image/png;base64,${iconData}`;
                image.addEventListener("error", () => {
                    icon.classList.remove("has-native-icon");
                    image.remove();
                }, { once: true });
                icon.classList.add("has-native-icon");
                icon.append(image);
            }
            const name = document.createElement("span");
            name.className = "file-name";
            name.textContent = item.name;
            nameCell.append(icon, name);
            const modified = document.createElement("span");
            modified.className = "file-modified";
            modified.textContent = item.modified || "";
            const size = document.createElement("span");
            size.className = "file-size";
            size.textContent = item.size == null ? "--" : formatSize(item.size);
            row.append(nameCell, modified, size);
            elements.fileList.append(row);
        });
        updateSelectedItem();

        const hasItems = items.length > 0;
        elements.browserMessage.hidden = hasItems;
        elements.fileList.hidden = !hasItems;
        if (!hasItems) {
            elements.emptyTitle.textContent = state.currentLocation?.error
                ? "Couldn't access this location"
                : state.searchQuery
                    ? "No matching files"
                    : state.currentLocation?.emptyTitle || "This folder is empty";
            elements.emptyDescription.textContent = state.currentLocation?.error
                ? "Try Full Disk Access in System Settings, then choose this location again."
                : state.searchQuery
                    ? "Try a different name."
                    : state.currentLocation?.message || "";
        }
    }

    function compareItems(left, right) {
        if (Boolean(left.isDirectory) !== Boolean(right.isDirectory)) {
            return left.isDirectory ? -1 : 1;
        }
        let comparison = 0;
        if (state.sortBy === "modified") {
            comparison = (right.modifiedTimestamp ?? 0) - (left.modifiedTimestamp ?? 0);
        } else if (state.sortBy === "size") {
            comparison = (right.size ?? -1) - (left.size ?? -1);
        } else {
            comparison = nameCollator.compare(left.name, right.name);
        }
        return comparison || nameCollator.compare(left.name, right.name);
    }

    function iconGlyph(kind) {
        switch (kind) {
        case "folder": return "▰";
        case "application": return "▣";
        case "image": return "▧";
        case "audio": return "♫";
        case "video": return "▶";
        case "archive": return "▤";
        default: return "▤";
        }
    }

    function formatSize(bytes) {
        if (typeof bytes !== "number" || bytes < 0) return "";
        if (bytes < 1000) return `${bytes} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let size = bytes / 1000;
        let unit = 0;
        while (size >= 1000 && unit < units.length - 1) {
            size /= 1000;
            unit += 1;
        }
        return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[unit]}`;
    }

    function goBack() {
        const previous = state.backStack.pop();
        if (!previous) return;
        state.forwardStack.push(state.currentLocation);
        showDirectory(previous);
    }

    function goForward() {
        const next = state.forwardStack.pop();
        if (!next) return;
        state.backStack.push(state.currentLocation);
        showDirectory(next);
    }

    function updateNavigationButtons() {
        elements.backButton.disabled = state.backStack.length === 0;
        elements.forwardButton.disabled = state.forwardStack.length === 0;
    }

    function showMessage(title, message) {
        state.currentLocation = {
            title,
            message,
            items: []
        };
        renderItems();
    }

    return {
        initialize,
        renderSidebar,
        showLocation,
        showDirectory,
        openItemFromMenu,
        setViewMode
    };
})();

document.addEventListener("DOMContentLoaded", App.initialize);

window.FindMyFiles = Object.freeze({
    renderSidebar: App.renderSidebar,
    showLocation: App.showLocation,
    showDirectory: App.showDirectory,
    openItemFromMenu: App.openItemFromMenu,
    setViewMode: App.setViewMode
});
