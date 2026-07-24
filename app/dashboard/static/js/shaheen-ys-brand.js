(function () {
    "use strict";

    const BRAND_NAME = "SHAHEEN-YS";

    document.title = BRAND_NAME;

    document.documentElement
        .setAttribute(
            "data-brand",
            "shaheen-ys"
        );

    window.SHAHEEN_YS_BRAND = Object.freeze({
        name: BRAND_NAME,
        theme: "premium-modern",
        defaultMode: "dark"
    });
})();
