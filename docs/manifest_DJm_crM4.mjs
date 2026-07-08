import '@astrojs/internal-helpers/path';
import '@astrojs/internal-helpers/remote';
import 'piccolore';
import { N as NOOP_MIDDLEWARE_HEADER, h as decodeKey } from './chunks/astro/server_WUFD8Sh7.mjs';
import 'clsx';
import 'es-module-lexer';
import 'html-escaper';

const NOOP_MIDDLEWARE_FN = async (_ctx, next) => {
  const response = await next();
  response.headers.set(NOOP_MIDDLEWARE_HEADER, "true");
  return response;
};

const codeToStatusMap = {
  // Implemented from IANA HTTP Status Code Registry
  // https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  PAYMENT_REQUIRED: 402,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  METHOD_NOT_ALLOWED: 405,
  NOT_ACCEPTABLE: 406,
  PROXY_AUTHENTICATION_REQUIRED: 407,
  REQUEST_TIMEOUT: 408,
  CONFLICT: 409,
  GONE: 410,
  LENGTH_REQUIRED: 411,
  PRECONDITION_FAILED: 412,
  CONTENT_TOO_LARGE: 413,
  URI_TOO_LONG: 414,
  UNSUPPORTED_MEDIA_TYPE: 415,
  RANGE_NOT_SATISFIABLE: 416,
  EXPECTATION_FAILED: 417,
  MISDIRECTED_REQUEST: 421,
  UNPROCESSABLE_CONTENT: 422,
  LOCKED: 423,
  FAILED_DEPENDENCY: 424,
  TOO_EARLY: 425,
  UPGRADE_REQUIRED: 426,
  PRECONDITION_REQUIRED: 428,
  TOO_MANY_REQUESTS: 429,
  REQUEST_HEADER_FIELDS_TOO_LARGE: 431,
  UNAVAILABLE_FOR_LEGAL_REASONS: 451,
  INTERNAL_SERVER_ERROR: 500,
  NOT_IMPLEMENTED: 501,
  BAD_GATEWAY: 502,
  SERVICE_UNAVAILABLE: 503,
  GATEWAY_TIMEOUT: 504,
  HTTP_VERSION_NOT_SUPPORTED: 505,
  VARIANT_ALSO_NEGOTIATES: 506,
  INSUFFICIENT_STORAGE: 507,
  LOOP_DETECTED: 508,
  NETWORK_AUTHENTICATION_REQUIRED: 511
};
Object.entries(codeToStatusMap).reduce(
  // reverse the key-value pairs
  (acc, [key, value]) => ({ ...acc, [value]: key }),
  {}
);

function sanitizeParams(params) {
  return Object.fromEntries(
    Object.entries(params).map(([key, value]) => {
      if (typeof value === "string") {
        return [key, value.normalize().replace(/#/g, "%23").replace(/\?/g, "%3F")];
      }
      return [key, value];
    })
  );
}
function getParameter(part, params) {
  if (part.spread) {
    return params[part.content.slice(3)] || "";
  }
  if (part.dynamic) {
    if (!params[part.content]) {
      throw new TypeError(`Missing parameter: ${part.content}`);
    }
    return params[part.content];
  }
  return part.content.normalize().replace(/\?/g, "%3F").replace(/#/g, "%23").replace(/%5B/g, "[").replace(/%5D/g, "]");
}
function getSegment(segment, params) {
  const segmentPath = segment.map((part) => getParameter(part, params)).join("");
  return segmentPath ? "/" + segmentPath : "";
}
function getRouteGenerator(segments, addTrailingSlash) {
  return (params) => {
    const sanitizedParams = sanitizeParams(params);
    let trailing = "";
    if (addTrailingSlash === "always" && segments.length) {
      trailing = "/";
    }
    const path = segments.map((segment) => getSegment(segment, sanitizedParams)).join("") + trailing;
    return path || "/";
  };
}

function deserializeRouteData(rawRouteData) {
  return {
    route: rawRouteData.route,
    type: rawRouteData.type,
    pattern: new RegExp(rawRouteData.pattern),
    params: rawRouteData.params,
    component: rawRouteData.component,
    generate: getRouteGenerator(rawRouteData.segments, rawRouteData._meta.trailingSlash),
    pathname: rawRouteData.pathname || void 0,
    segments: rawRouteData.segments,
    prerender: rawRouteData.prerender,
    redirect: rawRouteData.redirect,
    redirectRoute: rawRouteData.redirectRoute ? deserializeRouteData(rawRouteData.redirectRoute) : void 0,
    fallbackRoutes: rawRouteData.fallbackRoutes.map((fallback) => {
      return deserializeRouteData(fallback);
    }),
    isIndex: rawRouteData.isIndex,
    origin: rawRouteData.origin
  };
}

function deserializeManifest(serializedManifest) {
  const routes = [];
  for (const serializedRoute of serializedManifest.routes) {
    routes.push({
      ...serializedRoute,
      routeData: deserializeRouteData(serializedRoute.routeData)
    });
    const route = serializedRoute;
    route.routeData = deserializeRouteData(serializedRoute.routeData);
  }
  const assets = new Set(serializedManifest.assets);
  const componentMetadata = new Map(serializedManifest.componentMetadata);
  const inlinedScripts = new Map(serializedManifest.inlinedScripts);
  const clientDirectives = new Map(serializedManifest.clientDirectives);
  const serverIslandNameMap = new Map(serializedManifest.serverIslandNameMap);
  const key = decodeKey(serializedManifest.key);
  return {
    // in case user middleware exists, this no-op middleware will be reassigned (see plugin-ssr.ts)
    middleware() {
      return { onRequest: NOOP_MIDDLEWARE_FN };
    },
    ...serializedManifest,
    assets,
    componentMetadata,
    inlinedScripts,
    clientDirectives,
    routes,
    serverIslandNameMap,
    key
  };
}

const manifest = deserializeManifest({"hrefRoot":"file:///Users/jack/Projects/osx/osx-ide/web/","cacheDir":"file:///Users/jack/Projects/osx/osx-ide/web/node_modules/.astro/","outDir":"file:///Users/jack/Projects/osx/osx-ide/docs/","srcDir":"file:///Users/jack/Projects/osx/osx-ide/web/src/","publicDir":"file:///Users/jack/Projects/osx/osx-ide/web/public/","buildClientDir":"file:///Users/jack/Projects/osx/osx-ide/docs/client/","buildServerDir":"file:///Users/jack/Projects/osx/osx-ide/docs/server/","adapterName":"","routes":[{"file":"file:///Users/jack/Projects/osx/osx-ide/docs/404.html","links":[],"scripts":[],"styles":[{"type":"external","src":"/ai-ide/_astro/beta.E-LtNaP4.css"}],"routeData":{"route":"/404","isIndex":false,"type":"page","pattern":"^\\/404\\/?$","segments":[[{"content":"404","dynamic":false,"spread":false}]],"params":[],"component":"src/pages/404.astro","pathname":"/404","prerender":true,"fallbackRoutes":[],"distURL":[],"origin":"project","_meta":{"trailingSlash":"ignore"}}},{"file":"file:///Users/jack/Projects/osx/osx-ide/docs/beta/index.html","links":[],"scripts":[],"styles":[{"type":"external","src":"/ai-ide/_astro/beta.E-LtNaP4.css"}],"routeData":{"route":"/beta","isIndex":false,"type":"page","pattern":"^\\/beta\\/?$","segments":[[{"content":"beta","dynamic":false,"spread":false}]],"params":[],"component":"src/pages/beta.astro","pathname":"/beta","prerender":true,"fallbackRoutes":[],"distURL":[],"origin":"project","_meta":{"trailingSlash":"ignore"}}},{"file":"file:///Users/jack/Projects/osx/osx-ide/docs/contributors/index.html","links":[],"scripts":[],"styles":[{"type":"external","src":"/ai-ide/_astro/beta.E-LtNaP4.css"}],"routeData":{"route":"/contributors","isIndex":false,"type":"page","pattern":"^\\/contributors\\/?$","segments":[[{"content":"contributors","dynamic":false,"spread":false}]],"params":[],"component":"src/pages/contributors.astro","pathname":"/contributors","prerender":true,"fallbackRoutes":[],"distURL":[],"origin":"project","_meta":{"trailingSlash":"ignore"}}},{"file":"file:///Users/jack/Projects/osx/osx-ide/docs/investors/index.html","links":[],"scripts":[],"styles":[{"type":"external","src":"/ai-ide/_astro/beta.E-LtNaP4.css"}],"routeData":{"route":"/investors","isIndex":false,"type":"page","pattern":"^\\/investors\\/?$","segments":[[{"content":"investors","dynamic":false,"spread":false}]],"params":[],"component":"src/pages/investors.astro","pathname":"/investors","prerender":true,"fallbackRoutes":[],"distURL":[],"origin":"project","_meta":{"trailingSlash":"ignore"}}},{"file":"file:///Users/jack/Projects/osx/osx-ide/docs/tech/index.html","links":[],"scripts":[],"styles":[{"type":"external","src":"/ai-ide/_astro/beta.E-LtNaP4.css"}],"routeData":{"route":"/tech","isIndex":false,"type":"page","pattern":"^\\/tech\\/?$","segments":[[{"content":"tech","dynamic":false,"spread":false}]],"params":[],"component":"src/pages/tech.astro","pathname":"/tech","prerender":true,"fallbackRoutes":[],"distURL":[],"origin":"project","_meta":{"trailingSlash":"ignore"}}},{"file":"file:///Users/jack/Projects/osx/osx-ide/docs/index.html","links":[],"scripts":[],"styles":[{"type":"external","src":"/ai-ide/_astro/beta.E-LtNaP4.css"}],"routeData":{"route":"/","isIndex":true,"type":"page","pattern":"^\\/$","segments":[],"params":[],"component":"src/pages/index.astro","pathname":"/","prerender":true,"fallbackRoutes":[],"distURL":[],"origin":"project","_meta":{"trailingSlash":"ignore"}}}],"site":"https://jtrefon.github.io/ai-ide/","base":"/ai-ide","trailingSlash":"ignore","compressHTML":true,"componentMetadata":[["/Users/jack/Projects/osx/osx-ide/web/src/pages/404.astro",{"propagation":"none","containsHead":true}],["/Users/jack/Projects/osx/osx-ide/web/src/pages/beta.astro",{"propagation":"none","containsHead":true}],["/Users/jack/Projects/osx/osx-ide/web/src/pages/contributors.astro",{"propagation":"none","containsHead":true}],["/Users/jack/Projects/osx/osx-ide/web/src/pages/index.astro",{"propagation":"none","containsHead":true}],["/Users/jack/Projects/osx/osx-ide/web/src/pages/investors.astro",{"propagation":"none","containsHead":true}],["/Users/jack/Projects/osx/osx-ide/web/src/pages/tech.astro",{"propagation":"none","containsHead":true}]],"renderers":[],"clientDirectives":[["idle","(()=>{var l=(n,t)=>{let i=async()=>{await(await n())()},e=typeof t.value==\"object\"?t.value:void 0,s={timeout:e==null?void 0:e.timeout};\"requestIdleCallback\"in window?window.requestIdleCallback(i,s):setTimeout(i,s.timeout||200)};(self.Astro||(self.Astro={})).idle=l;window.dispatchEvent(new Event(\"astro:idle\"));})();"],["load","(()=>{var e=async t=>{await(await t())()};(self.Astro||(self.Astro={})).load=e;window.dispatchEvent(new Event(\"astro:load\"));})();"],["media","(()=>{var n=(a,t)=>{let i=async()=>{await(await a())()};if(t.value){let e=matchMedia(t.value);e.matches?i():e.addEventListener(\"change\",i,{once:!0})}};(self.Astro||(self.Astro={})).media=n;window.dispatchEvent(new Event(\"astro:media\"));})();"],["only","(()=>{var e=async t=>{await(await t())()};(self.Astro||(self.Astro={})).only=e;window.dispatchEvent(new Event(\"astro:only\"));})();"],["visible","(()=>{var a=(s,i,o)=>{let r=async()=>{await(await s())()},t=typeof i.value==\"object\"?i.value:void 0,c={rootMargin:t==null?void 0:t.rootMargin},n=new IntersectionObserver(e=>{for(let l of e)if(l.isIntersecting){n.disconnect(),r();break}},c);for(let e of o.children)n.observe(e)};(self.Astro||(self.Astro={})).visible=a;window.dispatchEvent(new Event(\"astro:visible\"));})();"]],"entryModules":{"\u0000@astro-page:src/pages/404@_@astro":"pages/404.astro.mjs","\u0000@astro-page:src/pages/beta@_@astro":"pages/beta.astro.mjs","\u0000@astro-page:src/pages/contributors@_@astro":"pages/contributors.astro.mjs","\u0000@astro-page:src/pages/index@_@astro":"pages/index.astro.mjs","\u0000@astro-page:src/pages/investors@_@astro":"pages/investors.astro.mjs","\u0000@astro-page:src/pages/tech@_@astro":"pages/tech.astro.mjs","\u0000@astro-renderers":"renderers.mjs","\u0000noop-middleware":"_noop-middleware.mjs","\u0000virtual:astro:actions/noop-entrypoint":"noop-entrypoint.mjs","\u0000@astrojs-manifest":"manifest_DJm_crM4.mjs","/Users/jack/Projects/osx/osx-ide/web/src/layouts/BaseLayout.astro?astro&type=script&index=0&lang.ts":"_astro/BaseLayout.astro_astro_type_script_index_0_lang.D4mqoewB.js","/Users/jack/Projects/osx/osx-ide/web/src/pages/beta.astro?astro&type=script&index=0&lang.ts":"_astro/beta.astro_astro_type_script_index_0_lang.BUiayfIx.js","astro:scripts/before-hydration.js":""},"inlinedScripts":[["/Users/jack/Projects/osx/osx-ide/web/src/layouts/BaseLayout.astro?astro&type=script&index=0&lang.ts","const t=document.querySelector(\".menu-toggle\"),o=document.getElementById(\"mobile-menu\");t&&o&&t.addEventListener(\"click\",()=>{const e=o.classList.toggle(\"open\");t.setAttribute(\"aria-expanded\",e)});const s=new IntersectionObserver(e=>{e.forEach(n=>{n.isIntersecting&&n.target.classList.add(\"visible\")})},{threshold:.1});document.querySelectorAll(\".reveal\").forEach(e=>s.observe(e));const r=document.getElementById(\"year\");r&&(r.textContent=new Date().getFullYear().toString());"],["/Users/jack/Projects/osx/osx-ide/web/src/pages/beta.astro?astro&type=script&index=0&lang.ts","const e=document.getElementById(\"beta-form\"),t=document.getElementById(\"form-status\");e&&e.addEventListener(\"submit\",async n=>{n.preventDefault(),t.textContent=\"Submitting...\",t.className=\"form-status\";try{const s=e.getAttribute(\"action\")||e.action;if(!s||s.includes(\"formspree.io/f/\")&&s.endsWith(\"/\")){t.textContent=\"⚠️ Form backend not configured. Please set BETA_FORM_ACTION in src/consts.ts. For now, email jack@example.com directly.\",t.className=\"form-status error\";return}const o=await fetch(s,{method:\"POST\",body:new FormData(e),headers:{Accept:\"application/json\"}});if(o.ok)t.textContent=\"✅ You're on the list. We'll be in touch when beta slots open.\",t.className=\"form-status success\",e.reset();else{const a=await o.json();t.textContent=a.error||\"Something went wrong. Please try again.\",t.className=\"form-status error\"}}catch{t.textContent=\"Network error. Please try again.\",t.className=\"form-status error\"}});"]],"assets":["/ai-ide/file:///Users/jack/Projects/osx/osx-ide/docs/404.html","/ai-ide/file:///Users/jack/Projects/osx/osx-ide/docs/beta/index.html","/ai-ide/file:///Users/jack/Projects/osx/osx-ide/docs/contributors/index.html","/ai-ide/file:///Users/jack/Projects/osx/osx-ide/docs/investors/index.html","/ai-ide/file:///Users/jack/Projects/osx/osx-ide/docs/tech/index.html","/ai-ide/file:///Users/jack/Projects/osx/osx-ide/docs/index.html"],"buildFormat":"directory","checkOrigin":false,"allowedDomains":[],"actionBodySizeLimit":1048576,"serverIslandNameMap":[],"key":"B6hKJv1JduVx69l+WphF2xayX2PUZHd8ulIERa7e3hs="});
if (manifest.sessionConfig) manifest.sessionConfig.driverModule = null;

export { manifest };
