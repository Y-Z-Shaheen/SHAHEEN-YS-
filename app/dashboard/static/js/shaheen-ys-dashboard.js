(() => {
    "use strict";

    const SHAHEEN = {
        name: "SHAHEEN-YS",
        version: "1.0.0",
    };

    function applyBranding() {
        document.documentElement.dataset.brand = SHAHEEN.name;

        const brandedElements = document.querySelectorAll(
            "[data-shaheen-brand-name]"
        );

        brandedElements.forEach((element) => {
            element.textContent = SHAHEEN.name;
        });

        const title = document.querySelector("title");

        if (title && !title.textContent.includes(SHAHEEN.name)) {
            title.textContent = `${SHAHEEN.name} Dashboard`;
        }
    }

    function initializeAnimations() {
        const elements = document.querySelectorAll(
            ".shaheen-fade-in"
        );

        elements.forEach((element, index) => {
            element.style.animationDelay = `${index * 45}ms`;
        });
    }

    function initialize() {
        applyBranding();
        initializeAnimations();
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            { once: true }
        );
    } else {
        initialize();
    }
})();
