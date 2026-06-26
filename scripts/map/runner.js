"use strict";
var __getOwnPropNames = Object.getOwnPropertyNames;
var __commonJS = (cb, mod) => function __require() {
  return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
};

// node_modules/web-tree-sitter/tree-sitter.js
var require_tree_sitter = __commonJS({
  "node_modules/web-tree-sitter/tree-sitter.js"(exports, module) {
    var Module = typeof Module != "undefined" ? Module : {};
    var ENVIRONMENT_IS_WEB = typeof window == "object";
    var ENVIRONMENT_IS_WORKER = typeof importScripts == "function";
    var ENVIRONMENT_IS_NODE = typeof process == "object" && typeof process.versions == "object" && typeof process.versions.node == "string";
    if (ENVIRONMENT_IS_NODE) {
    }
    var TreeSitter = function() {
      var initPromise;
      var document = typeof window == "object" ? {
        currentScript: window.document.currentScript
      } : null;
      class Parser {
        constructor() {
          this.initialize();
        }
        initialize() {
          throw new Error("cannot construct a Parser before calling `init()`");
        }
        static init(moduleOptions) {
          if (initPromise) return initPromise;
          Module = Object.assign({}, Module, moduleOptions);
          return initPromise = new Promise((resolveInitPromise) => {
            var moduleOverrides = Object.assign({}, Module);
            var arguments_ = [];
            var thisProgram = "./this.program";
            var quit_ = (status, toThrow) => {
              throw toThrow;
            };
            var scriptDirectory = "";
            function locateFile(path) {
              if (Module["locateFile"]) {
                return Module["locateFile"](path, scriptDirectory);
              }
              return scriptDirectory + path;
            }
            var readAsync, readBinary;
            if (ENVIRONMENT_IS_NODE) {
              var fs = require("fs");
              var nodePath = require("path");
              scriptDirectory = __dirname + "/";
              readBinary = (filename) => {
                filename = isFileURI(filename) ? new URL(filename) : nodePath.normalize(filename);
                var ret = fs.readFileSync(filename);
                return ret;
              };
              readAsync = (filename, binary2 = true) => {
                filename = isFileURI(filename) ? new URL(filename) : nodePath.normalize(filename);
                return new Promise((resolve, reject) => {
                  fs.readFile(filename, binary2 ? void 0 : "utf8", (err2, data) => {
                    if (err2) reject(err2);
                    else resolve(binary2 ? data.buffer : data);
                  });
                });
              };
              if (!Module["thisProgram"] && process.argv.length > 1) {
                thisProgram = process.argv[1].replace(/\\/g, "/");
              }
              arguments_ = process.argv.slice(2);
              if (typeof module != "undefined") {
                module["exports"] = Module;
              }
              quit_ = (status, toThrow) => {
                process.exitCode = status;
                throw toThrow;
              };
            } else if (ENVIRONMENT_IS_WEB || ENVIRONMENT_IS_WORKER) {
              if (ENVIRONMENT_IS_WORKER) {
                scriptDirectory = self.location.href;
              } else if (typeof document != "undefined" && document.currentScript) {
                scriptDirectory = document.currentScript.src;
              }
              if (scriptDirectory.startsWith("blob:")) {
                scriptDirectory = "";
              } else {
                scriptDirectory = scriptDirectory.substr(0, scriptDirectory.replace(/[?#].*/, "").lastIndexOf("/") + 1);
              }
              {
                if (ENVIRONMENT_IS_WORKER) {
                  readBinary = (url) => {
                    var xhr = new XMLHttpRequest();
                    xhr.open("GET", url, false);
                    xhr.responseType = "arraybuffer";
                    xhr.send(null);
                    return new Uint8Array(
                      /** @type{!ArrayBuffer} */
                      xhr.response
                    );
                  };
                }
                readAsync = (url) => {
                  if (isFileURI(url)) {
                    return new Promise((reject, resolve) => {
                      var xhr = new XMLHttpRequest();
                      xhr.open("GET", url, true);
                      xhr.responseType = "arraybuffer";
                      xhr.onload = () => {
                        if (xhr.status == 200 || xhr.status == 0 && xhr.response) {
                          resolve(xhr.response);
                        }
                        reject(xhr.status);
                      };
                      xhr.onerror = reject;
                      xhr.send(null);
                    });
                  }
                  return fetch(url, {
                    credentials: "same-origin"
                  }).then((response) => {
                    if (response.ok) {
                      return response.arrayBuffer();
                    }
                    return Promise.reject(new Error(response.status + " : " + response.url));
                  });
                };
              }
            } else {
            }
            var out = Module["print"] || console.log.bind(console);
            var err = Module["printErr"] || console.error.bind(console);
            Object.assign(Module, moduleOverrides);
            moduleOverrides = null;
            if (Module["arguments"]) arguments_ = Module["arguments"];
            if (Module["thisProgram"]) thisProgram = Module["thisProgram"];
            if (Module["quit"]) quit_ = Module["quit"];
            var dynamicLibraries = Module["dynamicLibraries"] || [];
            var wasmBinary;
            if (Module["wasmBinary"]) wasmBinary = Module["wasmBinary"];
            var wasmMemory;
            var ABORT = false;
            var EXITSTATUS;
            var HEAP8, HEAPU8, HEAP16, HEAPU16, HEAP32, HEAPU32, HEAPF32, HEAPF64;
            var HEAP_DATA_VIEW;
            function updateMemoryViews() {
              var b = wasmMemory.buffer;
              Module["HEAP_DATA_VIEW"] = HEAP_DATA_VIEW = new DataView(b);
              Module["HEAP8"] = HEAP8 = new Int8Array(b);
              Module["HEAP16"] = HEAP16 = new Int16Array(b);
              Module["HEAPU8"] = HEAPU8 = new Uint8Array(b);
              Module["HEAPU16"] = HEAPU16 = new Uint16Array(b);
              Module["HEAP32"] = HEAP32 = new Int32Array(b);
              Module["HEAPU32"] = HEAPU32 = new Uint32Array(b);
              Module["HEAPF32"] = HEAPF32 = new Float32Array(b);
              Module["HEAPF64"] = HEAPF64 = new Float64Array(b);
            }
            if (Module["wasmMemory"]) {
              wasmMemory = Module["wasmMemory"];
            } else {
              var INITIAL_MEMORY = Module["INITIAL_MEMORY"] || 33554432;
              wasmMemory = new WebAssembly.Memory({
                "initial": INITIAL_MEMORY / 65536,
                // In theory we should not need to emit the maximum if we want "unlimited"
                // or 4GB of memory, but VMs error on that atm, see
                // https://github.com/emscripten-core/emscripten/issues/14130
                // And in the pthreads case we definitely need to emit a maximum. So
                // always emit one.
                "maximum": 2147483648 / 65536
              });
            }
            updateMemoryViews();
            var __ATPRERUN__ = [];
            var __ATINIT__ = [];
            var __ATMAIN__ = [];
            var __ATPOSTRUN__ = [];
            var __RELOC_FUNCS__ = [];
            var runtimeInitialized = false;
            function preRun() {
              if (Module["preRun"]) {
                if (typeof Module["preRun"] == "function") Module["preRun"] = [Module["preRun"]];
                while (Module["preRun"].length) {
                  addOnPreRun(Module["preRun"].shift());
                }
              }
              callRuntimeCallbacks(__ATPRERUN__);
            }
            function initRuntime() {
              runtimeInitialized = true;
              callRuntimeCallbacks(__RELOC_FUNCS__);
              callRuntimeCallbacks(__ATINIT__);
            }
            function preMain() {
              callRuntimeCallbacks(__ATMAIN__);
            }
            function postRun() {
              if (Module["postRun"]) {
                if (typeof Module["postRun"] == "function") Module["postRun"] = [Module["postRun"]];
                while (Module["postRun"].length) {
                  addOnPostRun(Module["postRun"].shift());
                }
              }
              callRuntimeCallbacks(__ATPOSTRUN__);
            }
            function addOnPreRun(cb) {
              __ATPRERUN__.unshift(cb);
            }
            function addOnInit(cb) {
              __ATINIT__.unshift(cb);
            }
            function addOnPostRun(cb) {
              __ATPOSTRUN__.unshift(cb);
            }
            var runDependencies = 0;
            var runDependencyWatcher = null;
            var dependenciesFulfilled = null;
            function getUniqueRunDependency(id) {
              return id;
            }
            function addRunDependency(id) {
              runDependencies++;
              Module["monitorRunDependencies"]?.(runDependencies);
            }
            function removeRunDependency(id) {
              runDependencies--;
              Module["monitorRunDependencies"]?.(runDependencies);
              if (runDependencies == 0) {
                if (runDependencyWatcher !== null) {
                  clearInterval(runDependencyWatcher);
                  runDependencyWatcher = null;
                }
                if (dependenciesFulfilled) {
                  var callback = dependenciesFulfilled;
                  dependenciesFulfilled = null;
                  callback();
                }
              }
            }
            function abort(what) {
              Module["onAbort"]?.(what);
              what = "Aborted(" + what + ")";
              err(what);
              ABORT = true;
              EXITSTATUS = 1;
              what += ". Build with -sASSERTIONS for more info.";
              var e = new WebAssembly.RuntimeError(what);
              throw e;
            }
            var dataURIPrefix = "data:application/octet-stream;base64,";
            var isDataURI = (filename) => filename.startsWith(dataURIPrefix);
            var isFileURI = (filename) => filename.startsWith("file://");
            function findWasmBinary() {
              var f = "tree-sitter.wasm";
              if (!isDataURI(f)) {
                return locateFile(f);
              }
              return f;
            }
            var wasmBinaryFile;
            function getBinarySync(file) {
              if (file == wasmBinaryFile && wasmBinary) {
                return new Uint8Array(wasmBinary);
              }
              if (readBinary) {
                return readBinary(file);
              }
              throw "both async and sync fetching of the wasm failed";
            }
            function getBinaryPromise(binaryFile) {
              if (!wasmBinary) {
                return readAsync(binaryFile).then(
                  (response) => new Uint8Array(
                    /** @type{!ArrayBuffer} */
                    response
                  ),
                  // Fall back to getBinarySync if readAsync fails
                  () => getBinarySync(binaryFile)
                );
              }
              return Promise.resolve().then(() => getBinarySync(binaryFile));
            }
            function instantiateArrayBuffer(binaryFile, imports, receiver) {
              return getBinaryPromise(binaryFile).then((binary2) => WebAssembly.instantiate(binary2, imports)).then(receiver, (reason) => {
                err(`failed to asynchronously prepare wasm: ${reason}`);
                abort(reason);
              });
            }
            function instantiateAsync(binary2, binaryFile, imports, callback) {
              if (!binary2 && typeof WebAssembly.instantiateStreaming == "function" && !isDataURI(binaryFile) && // Don't use streaming for file:// delivered objects in a webview, fetch them synchronously.
              !isFileURI(binaryFile) && // Avoid instantiateStreaming() on Node.js environment for now, as while
              // Node.js v18.1.0 implements it, it does not have a full fetch()
              // implementation yet.
              // Reference:
              //   https://github.com/emscripten-core/emscripten/pull/16917
              !ENVIRONMENT_IS_NODE && typeof fetch == "function") {
                return fetch(binaryFile, {
                  credentials: "same-origin"
                }).then((response) => {
                  var result = WebAssembly.instantiateStreaming(response, imports);
                  return result.then(callback, function(reason) {
                    err(`wasm streaming compile failed: ${reason}`);
                    err("falling back to ArrayBuffer instantiation");
                    return instantiateArrayBuffer(binaryFile, imports, callback);
                  });
                });
              }
              return instantiateArrayBuffer(binaryFile, imports, callback);
            }
            function getWasmImports() {
              return {
                "env": wasmImports,
                "wasi_snapshot_preview1": wasmImports,
                "GOT.mem": new Proxy(wasmImports, GOTHandler),
                "GOT.func": new Proxy(wasmImports, GOTHandler)
              };
            }
            function createWasm() {
              var info2 = getWasmImports();
              function receiveInstance(instance2, module2) {
                wasmExports = instance2.exports;
                wasmExports = relocateExports(wasmExports, 1024);
                var metadata2 = getDylinkMetadata(module2);
                if (metadata2.neededDynlibs) {
                  dynamicLibraries = metadata2.neededDynlibs.concat(dynamicLibraries);
                }
                mergeLibSymbols(wasmExports, "main");
                LDSO.init();
                loadDylibs();
                addOnInit(wasmExports["__wasm_call_ctors"]);
                __RELOC_FUNCS__.push(wasmExports["__wasm_apply_data_relocs"]);
                removeRunDependency("wasm-instantiate");
                return wasmExports;
              }
              addRunDependency("wasm-instantiate");
              function receiveInstantiationResult(result) {
                receiveInstance(result["instance"], result["module"]);
              }
              if (Module["instantiateWasm"]) {
                try {
                  return Module["instantiateWasm"](info2, receiveInstance);
                } catch (e) {
                  err(`Module.instantiateWasm callback failed with error: ${e}`);
                  return false;
                }
              }
              if (!wasmBinaryFile) wasmBinaryFile = findWasmBinary();
              instantiateAsync(wasmBinary, wasmBinaryFile, info2, receiveInstantiationResult);
              return {};
            }
            var ASM_CONSTS = {};
            function ExitStatus(status) {
              this.name = "ExitStatus";
              this.message = `Program terminated with exit(${status})`;
              this.status = status;
            }
            var GOT = {};
            var currentModuleWeakSymbols = /* @__PURE__ */ new Set([]);
            var GOTHandler = {
              get(obj, symName) {
                var rtn = GOT[symName];
                if (!rtn) {
                  rtn = GOT[symName] = new WebAssembly.Global({
                    "value": "i32",
                    "mutable": true
                  });
                }
                if (!currentModuleWeakSymbols.has(symName)) {
                  rtn.required = true;
                }
                return rtn;
              }
            };
            var LE_HEAP_LOAD_F32 = (byteOffset) => HEAP_DATA_VIEW.getFloat32(byteOffset, true);
            var LE_HEAP_LOAD_F64 = (byteOffset) => HEAP_DATA_VIEW.getFloat64(byteOffset, true);
            var LE_HEAP_LOAD_I16 = (byteOffset) => HEAP_DATA_VIEW.getInt16(byteOffset, true);
            var LE_HEAP_LOAD_I32 = (byteOffset) => HEAP_DATA_VIEW.getInt32(byteOffset, true);
            var LE_HEAP_LOAD_U32 = (byteOffset) => HEAP_DATA_VIEW.getUint32(byteOffset, true);
            var LE_HEAP_STORE_F32 = (byteOffset, value) => HEAP_DATA_VIEW.setFloat32(byteOffset, value, true);
            var LE_HEAP_STORE_F64 = (byteOffset, value) => HEAP_DATA_VIEW.setFloat64(byteOffset, value, true);
            var LE_HEAP_STORE_I16 = (byteOffset, value) => HEAP_DATA_VIEW.setInt16(byteOffset, value, true);
            var LE_HEAP_STORE_I32 = (byteOffset, value) => HEAP_DATA_VIEW.setInt32(byteOffset, value, true);
            var LE_HEAP_STORE_U32 = (byteOffset, value) => HEAP_DATA_VIEW.setUint32(byteOffset, value, true);
            var callRuntimeCallbacks = (callbacks) => {
              while (callbacks.length > 0) {
                callbacks.shift()(Module);
              }
            };
            var UTF8Decoder = typeof TextDecoder != "undefined" ? new TextDecoder() : void 0;
            var UTF8ArrayToString = (heapOrArray, idx, maxBytesToRead) => {
              var endIdx = idx + maxBytesToRead;
              var endPtr = idx;
              while (heapOrArray[endPtr] && !(endPtr >= endIdx)) ++endPtr;
              if (endPtr - idx > 16 && heapOrArray.buffer && UTF8Decoder) {
                return UTF8Decoder.decode(heapOrArray.subarray(idx, endPtr));
              }
              var str = "";
              while (idx < endPtr) {
                var u0 = heapOrArray[idx++];
                if (!(u0 & 128)) {
                  str += String.fromCharCode(u0);
                  continue;
                }
                var u1 = heapOrArray[idx++] & 63;
                if ((u0 & 224) == 192) {
                  str += String.fromCharCode((u0 & 31) << 6 | u1);
                  continue;
                }
                var u2 = heapOrArray[idx++] & 63;
                if ((u0 & 240) == 224) {
                  u0 = (u0 & 15) << 12 | u1 << 6 | u2;
                } else {
                  u0 = (u0 & 7) << 18 | u1 << 12 | u2 << 6 | heapOrArray[idx++] & 63;
                }
                if (u0 < 65536) {
                  str += String.fromCharCode(u0);
                } else {
                  var ch = u0 - 65536;
                  str += String.fromCharCode(55296 | ch >> 10, 56320 | ch & 1023);
                }
              }
              return str;
            };
            var getDylinkMetadata = (binary2) => {
              var offset = 0;
              var end = 0;
              function getU8() {
                return binary2[offset++];
              }
              function getLEB() {
                var ret = 0;
                var mul = 1;
                while (1) {
                  var byte = binary2[offset++];
                  ret += (byte & 127) * mul;
                  mul *= 128;
                  if (!(byte & 128)) break;
                }
                return ret;
              }
              function getString() {
                var len = getLEB();
                offset += len;
                return UTF8ArrayToString(binary2, offset - len, len);
              }
              function failIf(condition, message) {
                if (condition) throw new Error(message);
              }
              var name2 = "dylink.0";
              if (binary2 instanceof WebAssembly.Module) {
                var dylinkSection = WebAssembly.Module.customSections(binary2, name2);
                if (dylinkSection.length === 0) {
                  name2 = "dylink";
                  dylinkSection = WebAssembly.Module.customSections(binary2, name2);
                }
                failIf(dylinkSection.length === 0, "need dylink section");
                binary2 = new Uint8Array(dylinkSection[0]);
                end = binary2.length;
              } else {
                var int32View = new Uint32Array(new Uint8Array(binary2.subarray(0, 24)).buffer);
                var magicNumberFound = int32View[0] == 1836278016 || int32View[0] == 6386541;
                failIf(!magicNumberFound, "need to see wasm magic number");
                failIf(binary2[8] !== 0, "need the dylink section to be first");
                offset = 9;
                var section_size = getLEB();
                end = offset + section_size;
                name2 = getString();
              }
              var customSection = {
                neededDynlibs: [],
                tlsExports: /* @__PURE__ */ new Set(),
                weakImports: /* @__PURE__ */ new Set()
              };
              if (name2 == "dylink") {
                customSection.memorySize = getLEB();
                customSection.memoryAlign = getLEB();
                customSection.tableSize = getLEB();
                customSection.tableAlign = getLEB();
                var neededDynlibsCount = getLEB();
                for (var i2 = 0; i2 < neededDynlibsCount; ++i2) {
                  var libname = getString();
                  customSection.neededDynlibs.push(libname);
                }
              } else {
                failIf(name2 !== "dylink.0");
                var WASM_DYLINK_MEM_INFO = 1;
                var WASM_DYLINK_NEEDED = 2;
                var WASM_DYLINK_EXPORT_INFO = 3;
                var WASM_DYLINK_IMPORT_INFO = 4;
                var WASM_SYMBOL_TLS = 256;
                var WASM_SYMBOL_BINDING_MASK = 3;
                var WASM_SYMBOL_BINDING_WEAK = 1;
                while (offset < end) {
                  var subsectionType = getU8();
                  var subsectionSize = getLEB();
                  if (subsectionType === WASM_DYLINK_MEM_INFO) {
                    customSection.memorySize = getLEB();
                    customSection.memoryAlign = getLEB();
                    customSection.tableSize = getLEB();
                    customSection.tableAlign = getLEB();
                  } else if (subsectionType === WASM_DYLINK_NEEDED) {
                    var neededDynlibsCount = getLEB();
                    for (var i2 = 0; i2 < neededDynlibsCount; ++i2) {
                      libname = getString();
                      customSection.neededDynlibs.push(libname);
                    }
                  } else if (subsectionType === WASM_DYLINK_EXPORT_INFO) {
                    var count = getLEB();
                    while (count--) {
                      var symname = getString();
                      var flags2 = getLEB();
                      if (flags2 & WASM_SYMBOL_TLS) {
                        customSection.tlsExports.add(symname);
                      }
                    }
                  } else if (subsectionType === WASM_DYLINK_IMPORT_INFO) {
                    var count = getLEB();
                    while (count--) {
                      var modname = getString();
                      var symname = getString();
                      var flags2 = getLEB();
                      if ((flags2 & WASM_SYMBOL_BINDING_MASK) == WASM_SYMBOL_BINDING_WEAK) {
                        customSection.weakImports.add(symname);
                      }
                    }
                  } else {
                    offset += subsectionSize;
                  }
                }
              }
              return customSection;
            };
            function getValue(ptr, type = "i8") {
              if (type.endsWith("*")) type = "*";
              switch (type) {
                case "i1":
                  return HEAP8[ptr];
                case "i8":
                  return HEAP8[ptr];
                case "i16":
                  return LE_HEAP_LOAD_I16((ptr >> 1) * 2);
                case "i32":
                  return LE_HEAP_LOAD_I32((ptr >> 2) * 4);
                case "i64":
                  abort("to do getValue(i64) use WASM_BIGINT");
                case "float":
                  return LE_HEAP_LOAD_F32((ptr >> 2) * 4);
                case "double":
                  return LE_HEAP_LOAD_F64((ptr >> 3) * 8);
                case "*":
                  return LE_HEAP_LOAD_U32((ptr >> 2) * 4);
                default:
                  abort(`invalid type for getValue: ${type}`);
              }
            }
            var newDSO = (name2, handle2, syms) => {
              var dso = {
                refcount: Infinity,
                name: name2,
                exports: syms,
                global: true
              };
              LDSO.loadedLibsByName[name2] = dso;
              if (handle2 != void 0) {
                LDSO.loadedLibsByHandle[handle2] = dso;
              }
              return dso;
            };
            var LDSO = {
              loadedLibsByName: {},
              loadedLibsByHandle: {},
              init() {
                newDSO("__main__", 0, wasmImports);
              }
            };
            var ___heap_base = 78112;
            var zeroMemory = (address, size) => {
              HEAPU8.fill(0, address, address + size);
              return address;
            };
            var alignMemory = (size, alignment) => Math.ceil(size / alignment) * alignment;
            var getMemory = (size) => {
              if (runtimeInitialized) {
                return zeroMemory(_malloc(size), size);
              }
              var ret = ___heap_base;
              var end = ret + alignMemory(size, 16);
              ___heap_base = end;
              GOT["__heap_base"].value = end;
              return ret;
            };
            var isInternalSym = (symName) => ["__cpp_exception", "__c_longjmp", "__wasm_apply_data_relocs", "__dso_handle", "__tls_size", "__tls_align", "__set_stack_limits", "_emscripten_tls_init", "__wasm_init_tls", "__wasm_call_ctors", "__start_em_asm", "__stop_em_asm", "__start_em_js", "__stop_em_js"].includes(symName) || symName.startsWith("__em_js__");
            var uleb128Encode = (n, target) => {
              if (n < 128) {
                target.push(n);
              } else {
                target.push(n % 128 | 128, n >> 7);
              }
            };
            var sigToWasmTypes = (sig) => {
              var typeNames = {
                "i": "i32",
                "j": "i64",
                "f": "f32",
                "d": "f64",
                "e": "externref",
                "p": "i32"
              };
              var type = {
                parameters: [],
                results: sig[0] == "v" ? [] : [typeNames[sig[0]]]
              };
              for (var i2 = 1; i2 < sig.length; ++i2) {
                type.parameters.push(typeNames[sig[i2]]);
              }
              return type;
            };
            var generateFuncType = (sig, target) => {
              var sigRet = sig.slice(0, 1);
              var sigParam = sig.slice(1);
              var typeCodes = {
                "i": 127,
                // i32
                "p": 127,
                // i32
                "j": 126,
                // i64
                "f": 125,
                // f32
                "d": 124,
                // f64
                "e": 111
              };
              target.push(96);
              uleb128Encode(sigParam.length, target);
              for (var i2 = 0; i2 < sigParam.length; ++i2) {
                target.push(typeCodes[sigParam[i2]]);
              }
              if (sigRet == "v") {
                target.push(0);
              } else {
                target.push(1, typeCodes[sigRet]);
              }
            };
            var convertJsFunctionToWasm = (func2, sig) => {
              if (typeof WebAssembly.Function == "function") {
                return new WebAssembly.Function(sigToWasmTypes(sig), func2);
              }
              var typeSectionBody = [1];
              generateFuncType(sig, typeSectionBody);
              var bytes = [
                0,
                97,
                115,
                109,
                // magic ("\0asm")
                1,
                0,
                0,
                0,
                // version: 1
                1
              ];
              uleb128Encode(typeSectionBody.length, bytes);
              bytes.push(...typeSectionBody);
              bytes.push(
                2,
                7,
                // import section
                // (import "e" "f" (func 0 (type 0)))
                1,
                1,
                101,
                1,
                102,
                0,
                0,
                7,
                5,
                // export section
                // (export "f" (func 0 (type 0)))
                1,
                1,
                102,
                0,
                0
              );
              var module2 = new WebAssembly.Module(new Uint8Array(bytes));
              var instance2 = new WebAssembly.Instance(module2, {
                "e": {
                  "f": func2
                }
              });
              var wrappedFunc = instance2.exports["f"];
              return wrappedFunc;
            };
            var wasmTableMirror = [];
            var wasmTable = new WebAssembly.Table({
              "initial": 28,
              "element": "anyfunc"
            });
            var getWasmTableEntry = (funcPtr) => {
              var func2 = wasmTableMirror[funcPtr];
              if (!func2) {
                if (funcPtr >= wasmTableMirror.length) wasmTableMirror.length = funcPtr + 1;
                wasmTableMirror[funcPtr] = func2 = wasmTable.get(funcPtr);
              }
              return func2;
            };
            var updateTableMap = (offset, count) => {
              if (functionsInTableMap) {
                for (var i2 = offset; i2 < offset + count; i2++) {
                  var item = getWasmTableEntry(i2);
                  if (item) {
                    functionsInTableMap.set(item, i2);
                  }
                }
              }
            };
            var functionsInTableMap;
            var getFunctionAddress = (func2) => {
              if (!functionsInTableMap) {
                functionsInTableMap = /* @__PURE__ */ new WeakMap();
                updateTableMap(0, wasmTable.length);
              }
              return functionsInTableMap.get(func2) || 0;
            };
            var freeTableIndexes = [];
            var getEmptyTableSlot = () => {
              if (freeTableIndexes.length) {
                return freeTableIndexes.pop();
              }
              try {
                wasmTable.grow(1);
              } catch (err2) {
                if (!(err2 instanceof RangeError)) {
                  throw err2;
                }
                throw "Unable to grow wasm table. Set ALLOW_TABLE_GROWTH.";
              }
              return wasmTable.length - 1;
            };
            var setWasmTableEntry = (idx, func2) => {
              wasmTable.set(idx, func2);
              wasmTableMirror[idx] = wasmTable.get(idx);
            };
            var addFunction = (func2, sig) => {
              var rtn = getFunctionAddress(func2);
              if (rtn) {
                return rtn;
              }
              var ret = getEmptyTableSlot();
              try {
                setWasmTableEntry(ret, func2);
              } catch (err2) {
                if (!(err2 instanceof TypeError)) {
                  throw err2;
                }
                var wrapped = convertJsFunctionToWasm(func2, sig);
                setWasmTableEntry(ret, wrapped);
              }
              functionsInTableMap.set(func2, ret);
              return ret;
            };
            var updateGOT = (exports2, replace) => {
              for (var symName in exports2) {
                if (isInternalSym(symName)) {
                  continue;
                }
                var value = exports2[symName];
                if (symName.startsWith("orig$")) {
                  symName = symName.split("$")[1];
                  replace = true;
                }
                GOT[symName] ||= new WebAssembly.Global({
                  "value": "i32",
                  "mutable": true
                });
                if (replace || GOT[symName].value == 0) {
                  if (typeof value == "function") {
                    GOT[symName].value = addFunction(value);
                  } else if (typeof value == "number") {
                    GOT[symName].value = value;
                  } else {
                    err(`unhandled export type for '${symName}': ${typeof value}`);
                  }
                }
              }
            };
            var relocateExports = (exports2, memoryBase2, replace) => {
              var relocated = {};
              for (var e in exports2) {
                var value = exports2[e];
                if (typeof value == "object") {
                  value = value.value;
                }
                if (typeof value == "number") {
                  value += memoryBase2;
                }
                relocated[e] = value;
              }
              updateGOT(relocated, replace);
              return relocated;
            };
            var isSymbolDefined = (symName) => {
              var existing = wasmImports[symName];
              if (!existing || existing.stub) {
                return false;
              }
              return true;
            };
            var dynCallLegacy = (sig, ptr, args2) => {
              sig = sig.replace(/p/g, "i");
              var f = Module["dynCall_" + sig];
              return f(ptr, ...args2);
            };
            var dynCall = (sig, ptr, args2 = []) => {
              if (sig.includes("j")) {
                return dynCallLegacy(sig, ptr, args2);
              }
              var rtn = getWasmTableEntry(ptr)(...args2);
              return rtn;
            };
            var stackSave = () => _emscripten_stack_get_current();
            var stackRestore = (val) => __emscripten_stack_restore(val);
            var createInvokeFunction = (sig) => (ptr, ...args2) => {
              var sp = stackSave();
              try {
                return dynCall(sig, ptr, args2);
              } catch (e) {
                stackRestore(sp);
                if (e !== e + 0) throw e;
                _setThrew(1, 0);
              }
            };
            var resolveGlobalSymbol = (symName, direct = false) => {
              var sym;
              if (direct && "orig$" + symName in wasmImports) {
                symName = "orig$" + symName;
              }
              if (isSymbolDefined(symName)) {
                sym = wasmImports[symName];
              } else if (symName.startsWith("invoke_")) {
                sym = wasmImports[symName] = createInvokeFunction(symName.split("_")[1]);
              }
              return {
                sym,
                name: symName
              };
            };
            var UTF8ToString = (ptr, maxBytesToRead) => ptr ? UTF8ArrayToString(HEAPU8, ptr, maxBytesToRead) : "";
            var loadWebAssemblyModule = (binary, flags, libName, localScope, handle) => {
              var metadata = getDylinkMetadata(binary);
              currentModuleWeakSymbols = metadata.weakImports;
              function loadModule() {
                var firstLoad = !handle || !HEAP8[handle + 8];
                if (firstLoad) {
                  var memAlign = Math.pow(2, metadata.memoryAlign);
                  var memoryBase = metadata.memorySize ? alignMemory(getMemory(metadata.memorySize + memAlign), memAlign) : 0;
                  var tableBase = metadata.tableSize ? wasmTable.length : 0;
                  if (handle) {
                    HEAP8[handle + 8] = 1;
                    LE_HEAP_STORE_U32((handle + 12 >> 2) * 4, memoryBase);
                    LE_HEAP_STORE_I32((handle + 16 >> 2) * 4, metadata.memorySize);
                    LE_HEAP_STORE_U32((handle + 20 >> 2) * 4, tableBase);
                    LE_HEAP_STORE_I32((handle + 24 >> 2) * 4, metadata.tableSize);
                  }
                } else {
                  memoryBase = LE_HEAP_LOAD_U32((handle + 12 >> 2) * 4);
                  tableBase = LE_HEAP_LOAD_U32((handle + 20 >> 2) * 4);
                }
                var tableGrowthNeeded = tableBase + metadata.tableSize - wasmTable.length;
                if (tableGrowthNeeded > 0) {
                  wasmTable.grow(tableGrowthNeeded);
                }
                var moduleExports;
                function resolveSymbol(sym) {
                  var resolved = resolveGlobalSymbol(sym).sym;
                  if (!resolved && localScope) {
                    resolved = localScope[sym];
                  }
                  if (!resolved) {
                    resolved = moduleExports[sym];
                  }
                  return resolved;
                }
                var proxyHandler = {
                  get(stubs, prop) {
                    switch (prop) {
                      case "__memory_base":
                        return memoryBase;
                      case "__table_base":
                        return tableBase;
                    }
                    if (prop in wasmImports && !wasmImports[prop].stub) {
                      return wasmImports[prop];
                    }
                    if (!(prop in stubs)) {
                      var resolved;
                      stubs[prop] = (...args2) => {
                        resolved ||= resolveSymbol(prop);
                        return resolved(...args2);
                      };
                    }
                    return stubs[prop];
                  }
                };
                var proxy = new Proxy({}, proxyHandler);
                var info = {
                  "GOT.mem": new Proxy({}, GOTHandler),
                  "GOT.func": new Proxy({}, GOTHandler),
                  "env": proxy,
                  "wasi_snapshot_preview1": proxy
                };
                function postInstantiation(module, instance) {
                  updateTableMap(tableBase, metadata.tableSize);
                  moduleExports = relocateExports(instance.exports, memoryBase);
                  if (!flags.allowUndefined) {
                    reportUndefinedSymbols();
                  }
                  function addEmAsm(addr, body) {
                    var args = [];
                    var arity = 0;
                    for (; arity < 16; arity++) {
                      if (body.indexOf("$" + arity) != -1) {
                        args.push("$" + arity);
                      } else {
                        break;
                      }
                    }
                    args = args.join(",");
                    var func = `(${args}) => { ${body} };`;
                    ASM_CONSTS[start] = eval(func);
                  }
                  if ("__start_em_asm" in moduleExports) {
                    var start = moduleExports["__start_em_asm"];
                    var stop = moduleExports["__stop_em_asm"];
                    while (start < stop) {
                      var jsString = UTF8ToString(start);
                      addEmAsm(start, jsString);
                      start = HEAPU8.indexOf(0, start) + 1;
                    }
                  }
                  function addEmJs(name, cSig, body) {
                    var jsArgs = [];
                    cSig = cSig.slice(1, -1);
                    if (cSig != "void") {
                      cSig = cSig.split(",");
                      for (var i in cSig) {
                        var jsArg = cSig[i].split(" ").pop();
                        jsArgs.push(jsArg.replace("*", ""));
                      }
                    }
                    var func = `(${jsArgs}) => ${body};`;
                    moduleExports[name] = eval(func);
                  }
                  for (var name in moduleExports) {
                    if (name.startsWith("__em_js__")) {
                      var start = moduleExports[name];
                      var jsString = UTF8ToString(start);
                      var parts = jsString.split("<::>");
                      addEmJs(name.replace("__em_js__", ""), parts[0], parts[1]);
                      delete moduleExports[name];
                    }
                  }
                  var applyRelocs = moduleExports["__wasm_apply_data_relocs"];
                  if (applyRelocs) {
                    if (runtimeInitialized) {
                      applyRelocs();
                    } else {
                      __RELOC_FUNCS__.push(applyRelocs);
                    }
                  }
                  var init = moduleExports["__wasm_call_ctors"];
                  if (init) {
                    if (runtimeInitialized) {
                      init();
                    } else {
                      __ATINIT__.push(init);
                    }
                  }
                  return moduleExports;
                }
                if (flags.loadAsync) {
                  if (binary instanceof WebAssembly.Module) {
                    var instance = new WebAssembly.Instance(binary, info);
                    return Promise.resolve(postInstantiation(binary, instance));
                  }
                  return WebAssembly.instantiate(binary, info).then((result) => postInstantiation(result.module, result.instance));
                }
                var module = binary instanceof WebAssembly.Module ? binary : new WebAssembly.Module(binary);
                var instance = new WebAssembly.Instance(module, info);
                return postInstantiation(module, instance);
              }
              if (flags.loadAsync) {
                return metadata.neededDynlibs.reduce((chain, dynNeeded) => chain.then(() => loadDynamicLibrary(dynNeeded, flags, localScope)), Promise.resolve()).then(loadModule);
              }
              metadata.neededDynlibs.forEach((needed) => loadDynamicLibrary(needed, flags, localScope));
              return loadModule();
            };
            var mergeLibSymbols = (exports2, libName2) => {
              for (var [sym, exp] of Object.entries(exports2)) {
                const setImport = (target) => {
                  if (!isSymbolDefined(target)) {
                    wasmImports[target] = exp;
                  }
                };
                setImport(sym);
                const main_alias = "__main_argc_argv";
                if (sym == "main") {
                  setImport(main_alias);
                }
                if (sym == main_alias) {
                  setImport("main");
                }
                if (sym.startsWith("dynCall_") && !Module.hasOwnProperty(sym)) {
                  Module[sym] = exp;
                }
              }
            };
            var asyncLoad = (url, onload, onerror, noRunDep) => {
              var dep = !noRunDep ? getUniqueRunDependency(`al ${url}`) : "";
              readAsync(url).then((arrayBuffer) => {
                onload(new Uint8Array(arrayBuffer));
                if (dep) removeRunDependency(dep);
              }, (err2) => {
                if (onerror) {
                  onerror();
                } else {
                  throw `Loading data file "${url}" failed.`;
                }
              });
              if (dep) addRunDependency(dep);
            };
            function loadDynamicLibrary(libName2, flags2 = {
              global: true,
              nodelete: true
            }, localScope2, handle2) {
              var dso = LDSO.loadedLibsByName[libName2];
              if (dso) {
                if (!flags2.global) {
                  if (localScope2) {
                    Object.assign(localScope2, dso.exports);
                  }
                } else if (!dso.global) {
                  dso.global = true;
                  mergeLibSymbols(dso.exports, libName2);
                }
                if (flags2.nodelete && dso.refcount !== Infinity) {
                  dso.refcount = Infinity;
                }
                dso.refcount++;
                if (handle2) {
                  LDSO.loadedLibsByHandle[handle2] = dso;
                }
                return flags2.loadAsync ? Promise.resolve(true) : true;
              }
              dso = newDSO(libName2, handle2, "loading");
              dso.refcount = flags2.nodelete ? Infinity : 1;
              dso.global = flags2.global;
              function loadLibData() {
                if (handle2) {
                  var data = LE_HEAP_LOAD_U32((handle2 + 28 >> 2) * 4);
                  var dataSize = LE_HEAP_LOAD_U32((handle2 + 32 >> 2) * 4);
                  if (data && dataSize) {
                    var libData = HEAP8.slice(data, data + dataSize);
                    return flags2.loadAsync ? Promise.resolve(libData) : libData;
                  }
                }
                var libFile = locateFile(libName2);
                if (flags2.loadAsync) {
                  return new Promise(function(resolve, reject) {
                    asyncLoad(libFile, resolve, reject);
                  });
                }
                if (!readBinary) {
                  throw new Error(`${libFile}: file not found, and synchronous loading of external files is not available`);
                }
                return readBinary(libFile);
              }
              function getExports() {
                if (flags2.loadAsync) {
                  return loadLibData().then((libData) => loadWebAssemblyModule(libData, flags2, libName2, localScope2, handle2));
                }
                return loadWebAssemblyModule(loadLibData(), flags2, libName2, localScope2, handle2);
              }
              function moduleLoaded(exports2) {
                if (dso.global) {
                  mergeLibSymbols(exports2, libName2);
                } else if (localScope2) {
                  Object.assign(localScope2, exports2);
                }
                dso.exports = exports2;
              }
              if (flags2.loadAsync) {
                return getExports().then((exports2) => {
                  moduleLoaded(exports2);
                  return true;
                });
              }
              moduleLoaded(getExports());
              return true;
            }
            var reportUndefinedSymbols = () => {
              for (var [symName, entry] of Object.entries(GOT)) {
                if (entry.value == 0) {
                  var value = resolveGlobalSymbol(symName, true).sym;
                  if (!value && !entry.required) {
                    continue;
                  }
                  if (typeof value == "function") {
                    entry.value = addFunction(value, value.sig);
                  } else if (typeof value == "number") {
                    entry.value = value;
                  } else {
                    throw new Error(`bad export type for '${symName}': ${typeof value}`);
                  }
                }
              }
            };
            var loadDylibs = () => {
              if (!dynamicLibraries.length) {
                reportUndefinedSymbols();
                return;
              }
              addRunDependency("loadDylibs");
              dynamicLibraries.reduce((chain, lib2) => chain.then(() => loadDynamicLibrary(lib2, {
                loadAsync: true,
                global: true,
                nodelete: true,
                allowUndefined: true
              })), Promise.resolve()).then(() => {
                reportUndefinedSymbols();
                removeRunDependency("loadDylibs");
              });
            };
            var noExitRuntime = Module["noExitRuntime"] || true;
            function setValue(ptr, value, type = "i8") {
              if (type.endsWith("*")) type = "*";
              switch (type) {
                case "i1":
                  HEAP8[ptr] = value;
                  break;
                case "i8":
                  HEAP8[ptr] = value;
                  break;
                case "i16":
                  LE_HEAP_STORE_I16((ptr >> 1) * 2, value);
                  break;
                case "i32":
                  LE_HEAP_STORE_I32((ptr >> 2) * 4, value);
                  break;
                case "i64":
                  abort("to do setValue(i64) use WASM_BIGINT");
                case "float":
                  LE_HEAP_STORE_F32((ptr >> 2) * 4, value);
                  break;
                case "double":
                  LE_HEAP_STORE_F64((ptr >> 3) * 8, value);
                  break;
                case "*":
                  LE_HEAP_STORE_U32((ptr >> 2) * 4, value);
                  break;
                default:
                  abort(`invalid type for setValue: ${type}`);
              }
            }
            var ___memory_base = new WebAssembly.Global({
              "value": "i32",
              "mutable": false
            }, 1024);
            var ___stack_pointer = new WebAssembly.Global({
              "value": "i32",
              "mutable": true
            }, 78112);
            var ___table_base = new WebAssembly.Global({
              "value": "i32",
              "mutable": false
            }, 1);
            var __abort_js = () => {
              abort("");
            };
            __abort_js.sig = "v";
            var nowIsMonotonic = 1;
            var __emscripten_get_now_is_monotonic = () => nowIsMonotonic;
            __emscripten_get_now_is_monotonic.sig = "i";
            var __emscripten_memcpy_js = (dest, src, num) => HEAPU8.copyWithin(dest, src, src + num);
            __emscripten_memcpy_js.sig = "vppp";
            var _emscripten_date_now = () => Date.now();
            _emscripten_date_now.sig = "d";
            var _emscripten_get_now;
            _emscripten_get_now = () => performance.now();
            _emscripten_get_now.sig = "d";
            var getHeapMax = () => (
              // Stay one Wasm page short of 4GB: while e.g. Chrome is able to allocate
              // full 4GB Wasm memories, the size will wrap back to 0 bytes in Wasm side
              // for any code that deals with heap sizes, which would require special
              // casing all heap size related code to treat 0 specially.
              2147483648
            );
            var growMemory = (size) => {
              var b = wasmMemory.buffer;
              var pages = (size - b.byteLength + 65535) / 65536;
              try {
                wasmMemory.grow(pages);
                updateMemoryViews();
                return 1;
              } catch (e) {
              }
            };
            var _emscripten_resize_heap = (requestedSize) => {
              var oldSize = HEAPU8.length;
              requestedSize >>>= 0;
              var maxHeapSize = getHeapMax();
              if (requestedSize > maxHeapSize) {
                return false;
              }
              var alignUp = (x, multiple) => x + (multiple - x % multiple) % multiple;
              for (var cutDown = 1; cutDown <= 4; cutDown *= 2) {
                var overGrownHeapSize = oldSize * (1 + 0.2 / cutDown);
                overGrownHeapSize = Math.min(overGrownHeapSize, requestedSize + 100663296);
                var newSize = Math.min(maxHeapSize, alignUp(Math.max(requestedSize, overGrownHeapSize), 65536));
                var replacement = growMemory(newSize);
                if (replacement) {
                  return true;
                }
              }
              return false;
            };
            _emscripten_resize_heap.sig = "ip";
            var _fd_close = (fd) => 52;
            _fd_close.sig = "ii";
            var convertI32PairToI53Checked = (lo, hi) => hi + 2097152 >>> 0 < 4194305 - !!lo ? (lo >>> 0) + hi * 4294967296 : NaN;
            function _fd_seek(fd, offset_low, offset_high, whence, newOffset) {
              var offset = convertI32PairToI53Checked(offset_low, offset_high);
              return 70;
            }
            _fd_seek.sig = "iiiiip";
            var printCharBuffers = [null, [], []];
            var printChar = (stream, curr) => {
              var buffer = printCharBuffers[stream];
              if (curr === 0 || curr === 10) {
                (stream === 1 ? out : err)(UTF8ArrayToString(buffer, 0));
                buffer.length = 0;
              } else {
                buffer.push(curr);
              }
            };
            var _fd_write = (fd, iov, iovcnt, pnum) => {
              var num = 0;
              for (var i2 = 0; i2 < iovcnt; i2++) {
                var ptr = LE_HEAP_LOAD_U32((iov >> 2) * 4);
                var len = LE_HEAP_LOAD_U32((iov + 4 >> 2) * 4);
                iov += 8;
                for (var j = 0; j < len; j++) {
                  printChar(fd, HEAPU8[ptr + j]);
                }
                num += len;
              }
              LE_HEAP_STORE_U32((pnum >> 2) * 4, num);
              return 0;
            };
            _fd_write.sig = "iippp";
            function _tree_sitter_log_callback(isLexMessage, messageAddress) {
              if (currentLogCallback) {
                const message = UTF8ToString(messageAddress);
                currentLogCallback(message, isLexMessage !== 0);
              }
            }
            function _tree_sitter_parse_callback(inputBufferAddress, index, row, column, lengthAddress) {
              const INPUT_BUFFER_SIZE = 10 * 1024;
              const string = currentParseCallback(index, {
                row,
                column
              });
              if (typeof string === "string") {
                setValue(lengthAddress, string.length, "i32");
                stringToUTF16(string, inputBufferAddress, INPUT_BUFFER_SIZE);
              } else {
                setValue(lengthAddress, 0, "i32");
              }
            }
            var runtimeKeepaliveCounter = 0;
            var keepRuntimeAlive = () => noExitRuntime || runtimeKeepaliveCounter > 0;
            var _proc_exit = (code) => {
              EXITSTATUS = code;
              if (!keepRuntimeAlive()) {
                Module["onExit"]?.(code);
                ABORT = true;
              }
              quit_(code, new ExitStatus(code));
            };
            _proc_exit.sig = "vi";
            var exitJS = (status, implicit) => {
              EXITSTATUS = status;
              _proc_exit(status);
            };
            var handleException = (e) => {
              if (e instanceof ExitStatus || e == "unwind") {
                return EXITSTATUS;
              }
              quit_(1, e);
            };
            var lengthBytesUTF8 = (str) => {
              var len = 0;
              for (var i2 = 0; i2 < str.length; ++i2) {
                var c = str.charCodeAt(i2);
                if (c <= 127) {
                  len++;
                } else if (c <= 2047) {
                  len += 2;
                } else if (c >= 55296 && c <= 57343) {
                  len += 4;
                  ++i2;
                } else {
                  len += 3;
                }
              }
              return len;
            };
            var stringToUTF8Array = (str, heap, outIdx, maxBytesToWrite) => {
              if (!(maxBytesToWrite > 0)) return 0;
              var startIdx = outIdx;
              var endIdx = outIdx + maxBytesToWrite - 1;
              for (var i2 = 0; i2 < str.length; ++i2) {
                var u = str.charCodeAt(i2);
                if (u >= 55296 && u <= 57343) {
                  var u1 = str.charCodeAt(++i2);
                  u = 65536 + ((u & 1023) << 10) | u1 & 1023;
                }
                if (u <= 127) {
                  if (outIdx >= endIdx) break;
                  heap[outIdx++] = u;
                } else if (u <= 2047) {
                  if (outIdx + 1 >= endIdx) break;
                  heap[outIdx++] = 192 | u >> 6;
                  heap[outIdx++] = 128 | u & 63;
                } else if (u <= 65535) {
                  if (outIdx + 2 >= endIdx) break;
                  heap[outIdx++] = 224 | u >> 12;
                  heap[outIdx++] = 128 | u >> 6 & 63;
                  heap[outIdx++] = 128 | u & 63;
                } else {
                  if (outIdx + 3 >= endIdx) break;
                  heap[outIdx++] = 240 | u >> 18;
                  heap[outIdx++] = 128 | u >> 12 & 63;
                  heap[outIdx++] = 128 | u >> 6 & 63;
                  heap[outIdx++] = 128 | u & 63;
                }
              }
              heap[outIdx] = 0;
              return outIdx - startIdx;
            };
            var stringToUTF8 = (str, outPtr, maxBytesToWrite) => stringToUTF8Array(str, HEAPU8, outPtr, maxBytesToWrite);
            var stackAlloc = (sz) => __emscripten_stack_alloc(sz);
            var stringToUTF8OnStack = (str) => {
              var size = lengthBytesUTF8(str) + 1;
              var ret = stackAlloc(size);
              stringToUTF8(str, ret, size);
              return ret;
            };
            var stringToUTF16 = (str, outPtr, maxBytesToWrite) => {
              maxBytesToWrite ??= 2147483647;
              if (maxBytesToWrite < 2) return 0;
              maxBytesToWrite -= 2;
              var startPtr = outPtr;
              var numCharsToWrite = maxBytesToWrite < str.length * 2 ? maxBytesToWrite / 2 : str.length;
              for (var i2 = 0; i2 < numCharsToWrite; ++i2) {
                var codeUnit = str.charCodeAt(i2);
                LE_HEAP_STORE_I16((outPtr >> 1) * 2, codeUnit);
                outPtr += 2;
              }
              LE_HEAP_STORE_I16((outPtr >> 1) * 2, 0);
              return outPtr - startPtr;
            };
            var AsciiToString = (ptr) => {
              var str = "";
              while (1) {
                var ch = HEAPU8[ptr++];
                if (!ch) return str;
                str += String.fromCharCode(ch);
              }
            };
            var wasmImports = {
              /** @export */
              __heap_base: ___heap_base,
              /** @export */
              __indirect_function_table: wasmTable,
              /** @export */
              __memory_base: ___memory_base,
              /** @export */
              __stack_pointer: ___stack_pointer,
              /** @export */
              __table_base: ___table_base,
              /** @export */
              _abort_js: __abort_js,
              /** @export */
              _emscripten_get_now_is_monotonic: __emscripten_get_now_is_monotonic,
              /** @export */
              _emscripten_memcpy_js: __emscripten_memcpy_js,
              /** @export */
              emscripten_get_now: _emscripten_get_now,
              /** @export */
              emscripten_resize_heap: _emscripten_resize_heap,
              /** @export */
              fd_close: _fd_close,
              /** @export */
              fd_seek: _fd_seek,
              /** @export */
              fd_write: _fd_write,
              /** @export */
              memory: wasmMemory,
              /** @export */
              tree_sitter_log_callback: _tree_sitter_log_callback,
              /** @export */
              tree_sitter_parse_callback: _tree_sitter_parse_callback
            };
            var wasmExports = createWasm();
            var ___wasm_call_ctors = () => (___wasm_call_ctors = wasmExports["__wasm_call_ctors"])();
            var ___wasm_apply_data_relocs = () => (___wasm_apply_data_relocs = wasmExports["__wasm_apply_data_relocs"])();
            var _malloc = Module["_malloc"] = (a0) => (_malloc = Module["_malloc"] = wasmExports["malloc"])(a0);
            var _calloc = Module["_calloc"] = (a0, a1) => (_calloc = Module["_calloc"] = wasmExports["calloc"])(a0, a1);
            var _realloc = Module["_realloc"] = (a0, a1) => (_realloc = Module["_realloc"] = wasmExports["realloc"])(a0, a1);
            var _free = Module["_free"] = (a0) => (_free = Module["_free"] = wasmExports["free"])(a0);
            var _ts_language_symbol_count = Module["_ts_language_symbol_count"] = (a0) => (_ts_language_symbol_count = Module["_ts_language_symbol_count"] = wasmExports["ts_language_symbol_count"])(a0);
            var _ts_language_state_count = Module["_ts_language_state_count"] = (a0) => (_ts_language_state_count = Module["_ts_language_state_count"] = wasmExports["ts_language_state_count"])(a0);
            var _ts_language_version = Module["_ts_language_version"] = (a0) => (_ts_language_version = Module["_ts_language_version"] = wasmExports["ts_language_version"])(a0);
            var _ts_language_field_count = Module["_ts_language_field_count"] = (a0) => (_ts_language_field_count = Module["_ts_language_field_count"] = wasmExports["ts_language_field_count"])(a0);
            var _ts_language_next_state = Module["_ts_language_next_state"] = (a0, a1, a2) => (_ts_language_next_state = Module["_ts_language_next_state"] = wasmExports["ts_language_next_state"])(a0, a1, a2);
            var _ts_language_symbol_name = Module["_ts_language_symbol_name"] = (a0, a1) => (_ts_language_symbol_name = Module["_ts_language_symbol_name"] = wasmExports["ts_language_symbol_name"])(a0, a1);
            var _ts_language_symbol_for_name = Module["_ts_language_symbol_for_name"] = (a0, a1, a2, a3) => (_ts_language_symbol_for_name = Module["_ts_language_symbol_for_name"] = wasmExports["ts_language_symbol_for_name"])(a0, a1, a2, a3);
            var _strncmp = Module["_strncmp"] = (a0, a1, a2) => (_strncmp = Module["_strncmp"] = wasmExports["strncmp"])(a0, a1, a2);
            var _ts_language_symbol_type = Module["_ts_language_symbol_type"] = (a0, a1) => (_ts_language_symbol_type = Module["_ts_language_symbol_type"] = wasmExports["ts_language_symbol_type"])(a0, a1);
            var _ts_language_field_name_for_id = Module["_ts_language_field_name_for_id"] = (a0, a1) => (_ts_language_field_name_for_id = Module["_ts_language_field_name_for_id"] = wasmExports["ts_language_field_name_for_id"])(a0, a1);
            var _ts_lookahead_iterator_new = Module["_ts_lookahead_iterator_new"] = (a0, a1) => (_ts_lookahead_iterator_new = Module["_ts_lookahead_iterator_new"] = wasmExports["ts_lookahead_iterator_new"])(a0, a1);
            var _ts_lookahead_iterator_delete = Module["_ts_lookahead_iterator_delete"] = (a0) => (_ts_lookahead_iterator_delete = Module["_ts_lookahead_iterator_delete"] = wasmExports["ts_lookahead_iterator_delete"])(a0);
            var _ts_lookahead_iterator_reset_state = Module["_ts_lookahead_iterator_reset_state"] = (a0, a1) => (_ts_lookahead_iterator_reset_state = Module["_ts_lookahead_iterator_reset_state"] = wasmExports["ts_lookahead_iterator_reset_state"])(a0, a1);
            var _ts_lookahead_iterator_reset = Module["_ts_lookahead_iterator_reset"] = (a0, a1, a2) => (_ts_lookahead_iterator_reset = Module["_ts_lookahead_iterator_reset"] = wasmExports["ts_lookahead_iterator_reset"])(a0, a1, a2);
            var _ts_lookahead_iterator_next = Module["_ts_lookahead_iterator_next"] = (a0) => (_ts_lookahead_iterator_next = Module["_ts_lookahead_iterator_next"] = wasmExports["ts_lookahead_iterator_next"])(a0);
            var _ts_lookahead_iterator_current_symbol = Module["_ts_lookahead_iterator_current_symbol"] = (a0) => (_ts_lookahead_iterator_current_symbol = Module["_ts_lookahead_iterator_current_symbol"] = wasmExports["ts_lookahead_iterator_current_symbol"])(a0);
            var _memset = Module["_memset"] = (a0, a1, a2) => (_memset = Module["_memset"] = wasmExports["memset"])(a0, a1, a2);
            var _memcpy = Module["_memcpy"] = (a0, a1, a2) => (_memcpy = Module["_memcpy"] = wasmExports["memcpy"])(a0, a1, a2);
            var _ts_parser_delete = Module["_ts_parser_delete"] = (a0) => (_ts_parser_delete = Module["_ts_parser_delete"] = wasmExports["ts_parser_delete"])(a0);
            var _ts_parser_reset = Module["_ts_parser_reset"] = (a0) => (_ts_parser_reset = Module["_ts_parser_reset"] = wasmExports["ts_parser_reset"])(a0);
            var _ts_parser_set_language = Module["_ts_parser_set_language"] = (a0, a1) => (_ts_parser_set_language = Module["_ts_parser_set_language"] = wasmExports["ts_parser_set_language"])(a0, a1);
            var _ts_parser_timeout_micros = Module["_ts_parser_timeout_micros"] = (a0) => (_ts_parser_timeout_micros = Module["_ts_parser_timeout_micros"] = wasmExports["ts_parser_timeout_micros"])(a0);
            var _ts_parser_set_timeout_micros = Module["_ts_parser_set_timeout_micros"] = (a0, a1, a2) => (_ts_parser_set_timeout_micros = Module["_ts_parser_set_timeout_micros"] = wasmExports["ts_parser_set_timeout_micros"])(a0, a1, a2);
            var _ts_parser_set_included_ranges = Module["_ts_parser_set_included_ranges"] = (a0, a1, a2) => (_ts_parser_set_included_ranges = Module["_ts_parser_set_included_ranges"] = wasmExports["ts_parser_set_included_ranges"])(a0, a1, a2);
            var _memmove = Module["_memmove"] = (a0, a1, a2) => (_memmove = Module["_memmove"] = wasmExports["memmove"])(a0, a1, a2);
            var _memcmp = Module["_memcmp"] = (a0, a1, a2) => (_memcmp = Module["_memcmp"] = wasmExports["memcmp"])(a0, a1, a2);
            var _ts_query_new = Module["_ts_query_new"] = (a0, a1, a2, a3, a4) => (_ts_query_new = Module["_ts_query_new"] = wasmExports["ts_query_new"])(a0, a1, a2, a3, a4);
            var _ts_query_delete = Module["_ts_query_delete"] = (a0) => (_ts_query_delete = Module["_ts_query_delete"] = wasmExports["ts_query_delete"])(a0);
            var _iswspace = Module["_iswspace"] = (a0) => (_iswspace = Module["_iswspace"] = wasmExports["iswspace"])(a0);
            var _iswalnum = Module["_iswalnum"] = (a0) => (_iswalnum = Module["_iswalnum"] = wasmExports["iswalnum"])(a0);
            var _ts_query_pattern_count = Module["_ts_query_pattern_count"] = (a0) => (_ts_query_pattern_count = Module["_ts_query_pattern_count"] = wasmExports["ts_query_pattern_count"])(a0);
            var _ts_query_capture_count = Module["_ts_query_capture_count"] = (a0) => (_ts_query_capture_count = Module["_ts_query_capture_count"] = wasmExports["ts_query_capture_count"])(a0);
            var _ts_query_string_count = Module["_ts_query_string_count"] = (a0) => (_ts_query_string_count = Module["_ts_query_string_count"] = wasmExports["ts_query_string_count"])(a0);
            var _ts_query_capture_name_for_id = Module["_ts_query_capture_name_for_id"] = (a0, a1, a2) => (_ts_query_capture_name_for_id = Module["_ts_query_capture_name_for_id"] = wasmExports["ts_query_capture_name_for_id"])(a0, a1, a2);
            var _ts_query_string_value_for_id = Module["_ts_query_string_value_for_id"] = (a0, a1, a2) => (_ts_query_string_value_for_id = Module["_ts_query_string_value_for_id"] = wasmExports["ts_query_string_value_for_id"])(a0, a1, a2);
            var _ts_query_predicates_for_pattern = Module["_ts_query_predicates_for_pattern"] = (a0, a1, a2) => (_ts_query_predicates_for_pattern = Module["_ts_query_predicates_for_pattern"] = wasmExports["ts_query_predicates_for_pattern"])(a0, a1, a2);
            var _ts_query_disable_capture = Module["_ts_query_disable_capture"] = (a0, a1, a2) => (_ts_query_disable_capture = Module["_ts_query_disable_capture"] = wasmExports["ts_query_disable_capture"])(a0, a1, a2);
            var _ts_tree_copy = Module["_ts_tree_copy"] = (a0) => (_ts_tree_copy = Module["_ts_tree_copy"] = wasmExports["ts_tree_copy"])(a0);
            var _ts_tree_delete = Module["_ts_tree_delete"] = (a0) => (_ts_tree_delete = Module["_ts_tree_delete"] = wasmExports["ts_tree_delete"])(a0);
            var _ts_init = Module["_ts_init"] = () => (_ts_init = Module["_ts_init"] = wasmExports["ts_init"])();
            var _ts_parser_new_wasm = Module["_ts_parser_new_wasm"] = () => (_ts_parser_new_wasm = Module["_ts_parser_new_wasm"] = wasmExports["ts_parser_new_wasm"])();
            var _ts_parser_enable_logger_wasm = Module["_ts_parser_enable_logger_wasm"] = (a0, a1) => (_ts_parser_enable_logger_wasm = Module["_ts_parser_enable_logger_wasm"] = wasmExports["ts_parser_enable_logger_wasm"])(a0, a1);
            var _ts_parser_parse_wasm = Module["_ts_parser_parse_wasm"] = (a0, a1, a2, a3, a4) => (_ts_parser_parse_wasm = Module["_ts_parser_parse_wasm"] = wasmExports["ts_parser_parse_wasm"])(a0, a1, a2, a3, a4);
            var _ts_parser_included_ranges_wasm = Module["_ts_parser_included_ranges_wasm"] = (a0) => (_ts_parser_included_ranges_wasm = Module["_ts_parser_included_ranges_wasm"] = wasmExports["ts_parser_included_ranges_wasm"])(a0);
            var _ts_language_type_is_named_wasm = Module["_ts_language_type_is_named_wasm"] = (a0, a1) => (_ts_language_type_is_named_wasm = Module["_ts_language_type_is_named_wasm"] = wasmExports["ts_language_type_is_named_wasm"])(a0, a1);
            var _ts_language_type_is_visible_wasm = Module["_ts_language_type_is_visible_wasm"] = (a0, a1) => (_ts_language_type_is_visible_wasm = Module["_ts_language_type_is_visible_wasm"] = wasmExports["ts_language_type_is_visible_wasm"])(a0, a1);
            var _ts_tree_root_node_wasm = Module["_ts_tree_root_node_wasm"] = (a0) => (_ts_tree_root_node_wasm = Module["_ts_tree_root_node_wasm"] = wasmExports["ts_tree_root_node_wasm"])(a0);
            var _ts_tree_root_node_with_offset_wasm = Module["_ts_tree_root_node_with_offset_wasm"] = (a0) => (_ts_tree_root_node_with_offset_wasm = Module["_ts_tree_root_node_with_offset_wasm"] = wasmExports["ts_tree_root_node_with_offset_wasm"])(a0);
            var _ts_tree_edit_wasm = Module["_ts_tree_edit_wasm"] = (a0) => (_ts_tree_edit_wasm = Module["_ts_tree_edit_wasm"] = wasmExports["ts_tree_edit_wasm"])(a0);
            var _ts_tree_included_ranges_wasm = Module["_ts_tree_included_ranges_wasm"] = (a0) => (_ts_tree_included_ranges_wasm = Module["_ts_tree_included_ranges_wasm"] = wasmExports["ts_tree_included_ranges_wasm"])(a0);
            var _ts_tree_get_changed_ranges_wasm = Module["_ts_tree_get_changed_ranges_wasm"] = (a0, a1) => (_ts_tree_get_changed_ranges_wasm = Module["_ts_tree_get_changed_ranges_wasm"] = wasmExports["ts_tree_get_changed_ranges_wasm"])(a0, a1);
            var _ts_tree_cursor_new_wasm = Module["_ts_tree_cursor_new_wasm"] = (a0) => (_ts_tree_cursor_new_wasm = Module["_ts_tree_cursor_new_wasm"] = wasmExports["ts_tree_cursor_new_wasm"])(a0);
            var _ts_tree_cursor_delete_wasm = Module["_ts_tree_cursor_delete_wasm"] = (a0) => (_ts_tree_cursor_delete_wasm = Module["_ts_tree_cursor_delete_wasm"] = wasmExports["ts_tree_cursor_delete_wasm"])(a0);
            var _ts_tree_cursor_reset_wasm = Module["_ts_tree_cursor_reset_wasm"] = (a0) => (_ts_tree_cursor_reset_wasm = Module["_ts_tree_cursor_reset_wasm"] = wasmExports["ts_tree_cursor_reset_wasm"])(a0);
            var _ts_tree_cursor_reset_to_wasm = Module["_ts_tree_cursor_reset_to_wasm"] = (a0, a1) => (_ts_tree_cursor_reset_to_wasm = Module["_ts_tree_cursor_reset_to_wasm"] = wasmExports["ts_tree_cursor_reset_to_wasm"])(a0, a1);
            var _ts_tree_cursor_goto_first_child_wasm = Module["_ts_tree_cursor_goto_first_child_wasm"] = (a0) => (_ts_tree_cursor_goto_first_child_wasm = Module["_ts_tree_cursor_goto_first_child_wasm"] = wasmExports["ts_tree_cursor_goto_first_child_wasm"])(a0);
            var _ts_tree_cursor_goto_last_child_wasm = Module["_ts_tree_cursor_goto_last_child_wasm"] = (a0) => (_ts_tree_cursor_goto_last_child_wasm = Module["_ts_tree_cursor_goto_last_child_wasm"] = wasmExports["ts_tree_cursor_goto_last_child_wasm"])(a0);
            var _ts_tree_cursor_goto_first_child_for_index_wasm = Module["_ts_tree_cursor_goto_first_child_for_index_wasm"] = (a0) => (_ts_tree_cursor_goto_first_child_for_index_wasm = Module["_ts_tree_cursor_goto_first_child_for_index_wasm"] = wasmExports["ts_tree_cursor_goto_first_child_for_index_wasm"])(a0);
            var _ts_tree_cursor_goto_first_child_for_position_wasm = Module["_ts_tree_cursor_goto_first_child_for_position_wasm"] = (a0) => (_ts_tree_cursor_goto_first_child_for_position_wasm = Module["_ts_tree_cursor_goto_first_child_for_position_wasm"] = wasmExports["ts_tree_cursor_goto_first_child_for_position_wasm"])(a0);
            var _ts_tree_cursor_goto_next_sibling_wasm = Module["_ts_tree_cursor_goto_next_sibling_wasm"] = (a0) => (_ts_tree_cursor_goto_next_sibling_wasm = Module["_ts_tree_cursor_goto_next_sibling_wasm"] = wasmExports["ts_tree_cursor_goto_next_sibling_wasm"])(a0);
            var _ts_tree_cursor_goto_previous_sibling_wasm = Module["_ts_tree_cursor_goto_previous_sibling_wasm"] = (a0) => (_ts_tree_cursor_goto_previous_sibling_wasm = Module["_ts_tree_cursor_goto_previous_sibling_wasm"] = wasmExports["ts_tree_cursor_goto_previous_sibling_wasm"])(a0);
            var _ts_tree_cursor_goto_descendant_wasm = Module["_ts_tree_cursor_goto_descendant_wasm"] = (a0, a1) => (_ts_tree_cursor_goto_descendant_wasm = Module["_ts_tree_cursor_goto_descendant_wasm"] = wasmExports["ts_tree_cursor_goto_descendant_wasm"])(a0, a1);
            var _ts_tree_cursor_goto_parent_wasm = Module["_ts_tree_cursor_goto_parent_wasm"] = (a0) => (_ts_tree_cursor_goto_parent_wasm = Module["_ts_tree_cursor_goto_parent_wasm"] = wasmExports["ts_tree_cursor_goto_parent_wasm"])(a0);
            var _ts_tree_cursor_current_node_type_id_wasm = Module["_ts_tree_cursor_current_node_type_id_wasm"] = (a0) => (_ts_tree_cursor_current_node_type_id_wasm = Module["_ts_tree_cursor_current_node_type_id_wasm"] = wasmExports["ts_tree_cursor_current_node_type_id_wasm"])(a0);
            var _ts_tree_cursor_current_node_state_id_wasm = Module["_ts_tree_cursor_current_node_state_id_wasm"] = (a0) => (_ts_tree_cursor_current_node_state_id_wasm = Module["_ts_tree_cursor_current_node_state_id_wasm"] = wasmExports["ts_tree_cursor_current_node_state_id_wasm"])(a0);
            var _ts_tree_cursor_current_node_is_named_wasm = Module["_ts_tree_cursor_current_node_is_named_wasm"] = (a0) => (_ts_tree_cursor_current_node_is_named_wasm = Module["_ts_tree_cursor_current_node_is_named_wasm"] = wasmExports["ts_tree_cursor_current_node_is_named_wasm"])(a0);
            var _ts_tree_cursor_current_node_is_missing_wasm = Module["_ts_tree_cursor_current_node_is_missing_wasm"] = (a0) => (_ts_tree_cursor_current_node_is_missing_wasm = Module["_ts_tree_cursor_current_node_is_missing_wasm"] = wasmExports["ts_tree_cursor_current_node_is_missing_wasm"])(a0);
            var _ts_tree_cursor_current_node_id_wasm = Module["_ts_tree_cursor_current_node_id_wasm"] = (a0) => (_ts_tree_cursor_current_node_id_wasm = Module["_ts_tree_cursor_current_node_id_wasm"] = wasmExports["ts_tree_cursor_current_node_id_wasm"])(a0);
            var _ts_tree_cursor_start_position_wasm = Module["_ts_tree_cursor_start_position_wasm"] = (a0) => (_ts_tree_cursor_start_position_wasm = Module["_ts_tree_cursor_start_position_wasm"] = wasmExports["ts_tree_cursor_start_position_wasm"])(a0);
            var _ts_tree_cursor_end_position_wasm = Module["_ts_tree_cursor_end_position_wasm"] = (a0) => (_ts_tree_cursor_end_position_wasm = Module["_ts_tree_cursor_end_position_wasm"] = wasmExports["ts_tree_cursor_end_position_wasm"])(a0);
            var _ts_tree_cursor_start_index_wasm = Module["_ts_tree_cursor_start_index_wasm"] = (a0) => (_ts_tree_cursor_start_index_wasm = Module["_ts_tree_cursor_start_index_wasm"] = wasmExports["ts_tree_cursor_start_index_wasm"])(a0);
            var _ts_tree_cursor_end_index_wasm = Module["_ts_tree_cursor_end_index_wasm"] = (a0) => (_ts_tree_cursor_end_index_wasm = Module["_ts_tree_cursor_end_index_wasm"] = wasmExports["ts_tree_cursor_end_index_wasm"])(a0);
            var _ts_tree_cursor_current_field_id_wasm = Module["_ts_tree_cursor_current_field_id_wasm"] = (a0) => (_ts_tree_cursor_current_field_id_wasm = Module["_ts_tree_cursor_current_field_id_wasm"] = wasmExports["ts_tree_cursor_current_field_id_wasm"])(a0);
            var _ts_tree_cursor_current_depth_wasm = Module["_ts_tree_cursor_current_depth_wasm"] = (a0) => (_ts_tree_cursor_current_depth_wasm = Module["_ts_tree_cursor_current_depth_wasm"] = wasmExports["ts_tree_cursor_current_depth_wasm"])(a0);
            var _ts_tree_cursor_current_descendant_index_wasm = Module["_ts_tree_cursor_current_descendant_index_wasm"] = (a0) => (_ts_tree_cursor_current_descendant_index_wasm = Module["_ts_tree_cursor_current_descendant_index_wasm"] = wasmExports["ts_tree_cursor_current_descendant_index_wasm"])(a0);
            var _ts_tree_cursor_current_node_wasm = Module["_ts_tree_cursor_current_node_wasm"] = (a0) => (_ts_tree_cursor_current_node_wasm = Module["_ts_tree_cursor_current_node_wasm"] = wasmExports["ts_tree_cursor_current_node_wasm"])(a0);
            var _ts_node_symbol_wasm = Module["_ts_node_symbol_wasm"] = (a0) => (_ts_node_symbol_wasm = Module["_ts_node_symbol_wasm"] = wasmExports["ts_node_symbol_wasm"])(a0);
            var _ts_node_field_name_for_child_wasm = Module["_ts_node_field_name_for_child_wasm"] = (a0, a1) => (_ts_node_field_name_for_child_wasm = Module["_ts_node_field_name_for_child_wasm"] = wasmExports["ts_node_field_name_for_child_wasm"])(a0, a1);
            var _ts_node_children_by_field_id_wasm = Module["_ts_node_children_by_field_id_wasm"] = (a0, a1) => (_ts_node_children_by_field_id_wasm = Module["_ts_node_children_by_field_id_wasm"] = wasmExports["ts_node_children_by_field_id_wasm"])(a0, a1);
            var _ts_node_first_child_for_byte_wasm = Module["_ts_node_first_child_for_byte_wasm"] = (a0) => (_ts_node_first_child_for_byte_wasm = Module["_ts_node_first_child_for_byte_wasm"] = wasmExports["ts_node_first_child_for_byte_wasm"])(a0);
            var _ts_node_first_named_child_for_byte_wasm = Module["_ts_node_first_named_child_for_byte_wasm"] = (a0) => (_ts_node_first_named_child_for_byte_wasm = Module["_ts_node_first_named_child_for_byte_wasm"] = wasmExports["ts_node_first_named_child_for_byte_wasm"])(a0);
            var _ts_node_grammar_symbol_wasm = Module["_ts_node_grammar_symbol_wasm"] = (a0) => (_ts_node_grammar_symbol_wasm = Module["_ts_node_grammar_symbol_wasm"] = wasmExports["ts_node_grammar_symbol_wasm"])(a0);
            var _ts_node_child_count_wasm = Module["_ts_node_child_count_wasm"] = (a0) => (_ts_node_child_count_wasm = Module["_ts_node_child_count_wasm"] = wasmExports["ts_node_child_count_wasm"])(a0);
            var _ts_node_named_child_count_wasm = Module["_ts_node_named_child_count_wasm"] = (a0) => (_ts_node_named_child_count_wasm = Module["_ts_node_named_child_count_wasm"] = wasmExports["ts_node_named_child_count_wasm"])(a0);
            var _ts_node_child_wasm = Module["_ts_node_child_wasm"] = (a0, a1) => (_ts_node_child_wasm = Module["_ts_node_child_wasm"] = wasmExports["ts_node_child_wasm"])(a0, a1);
            var _ts_node_named_child_wasm = Module["_ts_node_named_child_wasm"] = (a0, a1) => (_ts_node_named_child_wasm = Module["_ts_node_named_child_wasm"] = wasmExports["ts_node_named_child_wasm"])(a0, a1);
            var _ts_node_child_by_field_id_wasm = Module["_ts_node_child_by_field_id_wasm"] = (a0, a1) => (_ts_node_child_by_field_id_wasm = Module["_ts_node_child_by_field_id_wasm"] = wasmExports["ts_node_child_by_field_id_wasm"])(a0, a1);
            var _ts_node_next_sibling_wasm = Module["_ts_node_next_sibling_wasm"] = (a0) => (_ts_node_next_sibling_wasm = Module["_ts_node_next_sibling_wasm"] = wasmExports["ts_node_next_sibling_wasm"])(a0);
            var _ts_node_prev_sibling_wasm = Module["_ts_node_prev_sibling_wasm"] = (a0) => (_ts_node_prev_sibling_wasm = Module["_ts_node_prev_sibling_wasm"] = wasmExports["ts_node_prev_sibling_wasm"])(a0);
            var _ts_node_next_named_sibling_wasm = Module["_ts_node_next_named_sibling_wasm"] = (a0) => (_ts_node_next_named_sibling_wasm = Module["_ts_node_next_named_sibling_wasm"] = wasmExports["ts_node_next_named_sibling_wasm"])(a0);
            var _ts_node_prev_named_sibling_wasm = Module["_ts_node_prev_named_sibling_wasm"] = (a0) => (_ts_node_prev_named_sibling_wasm = Module["_ts_node_prev_named_sibling_wasm"] = wasmExports["ts_node_prev_named_sibling_wasm"])(a0);
            var _ts_node_descendant_count_wasm = Module["_ts_node_descendant_count_wasm"] = (a0) => (_ts_node_descendant_count_wasm = Module["_ts_node_descendant_count_wasm"] = wasmExports["ts_node_descendant_count_wasm"])(a0);
            var _ts_node_parent_wasm = Module["_ts_node_parent_wasm"] = (a0) => (_ts_node_parent_wasm = Module["_ts_node_parent_wasm"] = wasmExports["ts_node_parent_wasm"])(a0);
            var _ts_node_descendant_for_index_wasm = Module["_ts_node_descendant_for_index_wasm"] = (a0) => (_ts_node_descendant_for_index_wasm = Module["_ts_node_descendant_for_index_wasm"] = wasmExports["ts_node_descendant_for_index_wasm"])(a0);
            var _ts_node_named_descendant_for_index_wasm = Module["_ts_node_named_descendant_for_index_wasm"] = (a0) => (_ts_node_named_descendant_for_index_wasm = Module["_ts_node_named_descendant_for_index_wasm"] = wasmExports["ts_node_named_descendant_for_index_wasm"])(a0);
            var _ts_node_descendant_for_position_wasm = Module["_ts_node_descendant_for_position_wasm"] = (a0) => (_ts_node_descendant_for_position_wasm = Module["_ts_node_descendant_for_position_wasm"] = wasmExports["ts_node_descendant_for_position_wasm"])(a0);
            var _ts_node_named_descendant_for_position_wasm = Module["_ts_node_named_descendant_for_position_wasm"] = (a0) => (_ts_node_named_descendant_for_position_wasm = Module["_ts_node_named_descendant_for_position_wasm"] = wasmExports["ts_node_named_descendant_for_position_wasm"])(a0);
            var _ts_node_start_point_wasm = Module["_ts_node_start_point_wasm"] = (a0) => (_ts_node_start_point_wasm = Module["_ts_node_start_point_wasm"] = wasmExports["ts_node_start_point_wasm"])(a0);
            var _ts_node_end_point_wasm = Module["_ts_node_end_point_wasm"] = (a0) => (_ts_node_end_point_wasm = Module["_ts_node_end_point_wasm"] = wasmExports["ts_node_end_point_wasm"])(a0);
            var _ts_node_start_index_wasm = Module["_ts_node_start_index_wasm"] = (a0) => (_ts_node_start_index_wasm = Module["_ts_node_start_index_wasm"] = wasmExports["ts_node_start_index_wasm"])(a0);
            var _ts_node_end_index_wasm = Module["_ts_node_end_index_wasm"] = (a0) => (_ts_node_end_index_wasm = Module["_ts_node_end_index_wasm"] = wasmExports["ts_node_end_index_wasm"])(a0);
            var _ts_node_to_string_wasm = Module["_ts_node_to_string_wasm"] = (a0) => (_ts_node_to_string_wasm = Module["_ts_node_to_string_wasm"] = wasmExports["ts_node_to_string_wasm"])(a0);
            var _ts_node_children_wasm = Module["_ts_node_children_wasm"] = (a0) => (_ts_node_children_wasm = Module["_ts_node_children_wasm"] = wasmExports["ts_node_children_wasm"])(a0);
            var _ts_node_named_children_wasm = Module["_ts_node_named_children_wasm"] = (a0) => (_ts_node_named_children_wasm = Module["_ts_node_named_children_wasm"] = wasmExports["ts_node_named_children_wasm"])(a0);
            var _ts_node_descendants_of_type_wasm = Module["_ts_node_descendants_of_type_wasm"] = (a0, a1, a2, a3, a4, a5, a6) => (_ts_node_descendants_of_type_wasm = Module["_ts_node_descendants_of_type_wasm"] = wasmExports["ts_node_descendants_of_type_wasm"])(a0, a1, a2, a3, a4, a5, a6);
            var _ts_node_is_named_wasm = Module["_ts_node_is_named_wasm"] = (a0) => (_ts_node_is_named_wasm = Module["_ts_node_is_named_wasm"] = wasmExports["ts_node_is_named_wasm"])(a0);
            var _ts_node_has_changes_wasm = Module["_ts_node_has_changes_wasm"] = (a0) => (_ts_node_has_changes_wasm = Module["_ts_node_has_changes_wasm"] = wasmExports["ts_node_has_changes_wasm"])(a0);
            var _ts_node_has_error_wasm = Module["_ts_node_has_error_wasm"] = (a0) => (_ts_node_has_error_wasm = Module["_ts_node_has_error_wasm"] = wasmExports["ts_node_has_error_wasm"])(a0);
            var _ts_node_is_error_wasm = Module["_ts_node_is_error_wasm"] = (a0) => (_ts_node_is_error_wasm = Module["_ts_node_is_error_wasm"] = wasmExports["ts_node_is_error_wasm"])(a0);
            var _ts_node_is_missing_wasm = Module["_ts_node_is_missing_wasm"] = (a0) => (_ts_node_is_missing_wasm = Module["_ts_node_is_missing_wasm"] = wasmExports["ts_node_is_missing_wasm"])(a0);
            var _ts_node_is_extra_wasm = Module["_ts_node_is_extra_wasm"] = (a0) => (_ts_node_is_extra_wasm = Module["_ts_node_is_extra_wasm"] = wasmExports["ts_node_is_extra_wasm"])(a0);
            var _ts_node_parse_state_wasm = Module["_ts_node_parse_state_wasm"] = (a0) => (_ts_node_parse_state_wasm = Module["_ts_node_parse_state_wasm"] = wasmExports["ts_node_parse_state_wasm"])(a0);
            var _ts_node_next_parse_state_wasm = Module["_ts_node_next_parse_state_wasm"] = (a0) => (_ts_node_next_parse_state_wasm = Module["_ts_node_next_parse_state_wasm"] = wasmExports["ts_node_next_parse_state_wasm"])(a0);
            var _ts_query_matches_wasm = Module["_ts_query_matches_wasm"] = (a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) => (_ts_query_matches_wasm = Module["_ts_query_matches_wasm"] = wasmExports["ts_query_matches_wasm"])(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10);
            var _ts_query_captures_wasm = Module["_ts_query_captures_wasm"] = (a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) => (_ts_query_captures_wasm = Module["_ts_query_captures_wasm"] = wasmExports["ts_query_captures_wasm"])(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10);
            var _iswalpha = Module["_iswalpha"] = (a0) => (_iswalpha = Module["_iswalpha"] = wasmExports["iswalpha"])(a0);
            var _iswblank = Module["_iswblank"] = (a0) => (_iswblank = Module["_iswblank"] = wasmExports["iswblank"])(a0);
            var _iswdigit = Module["_iswdigit"] = (a0) => (_iswdigit = Module["_iswdigit"] = wasmExports["iswdigit"])(a0);
            var _iswlower = Module["_iswlower"] = (a0) => (_iswlower = Module["_iswlower"] = wasmExports["iswlower"])(a0);
            var _iswupper = Module["_iswupper"] = (a0) => (_iswupper = Module["_iswupper"] = wasmExports["iswupper"])(a0);
            var _iswxdigit = Module["_iswxdigit"] = (a0) => (_iswxdigit = Module["_iswxdigit"] = wasmExports["iswxdigit"])(a0);
            var _memchr = Module["_memchr"] = (a0, a1, a2) => (_memchr = Module["_memchr"] = wasmExports["memchr"])(a0, a1, a2);
            var _strlen = Module["_strlen"] = (a0) => (_strlen = Module["_strlen"] = wasmExports["strlen"])(a0);
            var _strcmp = Module["_strcmp"] = (a0, a1) => (_strcmp = Module["_strcmp"] = wasmExports["strcmp"])(a0, a1);
            var _strncat = Module["_strncat"] = (a0, a1, a2) => (_strncat = Module["_strncat"] = wasmExports["strncat"])(a0, a1, a2);
            var _strncpy = Module["_strncpy"] = (a0, a1, a2) => (_strncpy = Module["_strncpy"] = wasmExports["strncpy"])(a0, a1, a2);
            var _towlower = Module["_towlower"] = (a0) => (_towlower = Module["_towlower"] = wasmExports["towlower"])(a0);
            var _towupper = Module["_towupper"] = (a0) => (_towupper = Module["_towupper"] = wasmExports["towupper"])(a0);
            var _setThrew = (a0, a1) => (_setThrew = wasmExports["setThrew"])(a0, a1);
            var __emscripten_stack_restore = (a0) => (__emscripten_stack_restore = wasmExports["_emscripten_stack_restore"])(a0);
            var __emscripten_stack_alloc = (a0) => (__emscripten_stack_alloc = wasmExports["_emscripten_stack_alloc"])(a0);
            var _emscripten_stack_get_current = () => (_emscripten_stack_get_current = wasmExports["emscripten_stack_get_current"])();
            var dynCall_jiji = Module["dynCall_jiji"] = (a0, a1, a2, a3, a4) => (dynCall_jiji = Module["dynCall_jiji"] = wasmExports["dynCall_jiji"])(a0, a1, a2, a3, a4);
            var _orig$ts_parser_timeout_micros = Module["_orig$ts_parser_timeout_micros"] = (a0) => (_orig$ts_parser_timeout_micros = Module["_orig$ts_parser_timeout_micros"] = wasmExports["orig$ts_parser_timeout_micros"])(a0);
            var _orig$ts_parser_set_timeout_micros = Module["_orig$ts_parser_set_timeout_micros"] = (a0, a1) => (_orig$ts_parser_set_timeout_micros = Module["_orig$ts_parser_set_timeout_micros"] = wasmExports["orig$ts_parser_set_timeout_micros"])(a0, a1);
            Module["AsciiToString"] = AsciiToString;
            Module["stringToUTF16"] = stringToUTF16;
            var calledRun;
            dependenciesFulfilled = function runCaller() {
              if (!calledRun) run();
              if (!calledRun) dependenciesFulfilled = runCaller;
            };
            function callMain(args2 = []) {
              var entryFunction = resolveGlobalSymbol("main").sym;
              if (!entryFunction) return;
              args2.unshift(thisProgram);
              var argc = args2.length;
              var argv = stackAlloc((argc + 1) * 4);
              var argv_ptr = argv;
              args2.forEach((arg) => {
                LE_HEAP_STORE_U32((argv_ptr >> 2) * 4, stringToUTF8OnStack(arg));
                argv_ptr += 4;
              });
              LE_HEAP_STORE_U32((argv_ptr >> 2) * 4, 0);
              try {
                var ret = entryFunction(argc, argv);
                exitJS(
                  ret,
                  /* implicit = */
                  true
                );
                return ret;
              } catch (e) {
                return handleException(e);
              }
            }
            function run(args2 = arguments_) {
              if (runDependencies > 0) {
                return;
              }
              preRun();
              if (runDependencies > 0) {
                return;
              }
              function doRun() {
                if (calledRun) return;
                calledRun = true;
                Module["calledRun"] = true;
                if (ABORT) return;
                initRuntime();
                preMain();
                Module["onRuntimeInitialized"]?.();
                if (shouldRunNow) callMain(args2);
                postRun();
              }
              if (Module["setStatus"]) {
                Module["setStatus"]("Running...");
                setTimeout(function() {
                  setTimeout(function() {
                    Module["setStatus"]("");
                  }, 1);
                  doRun();
                }, 1);
              } else {
                doRun();
              }
            }
            if (Module["preInit"]) {
              if (typeof Module["preInit"] == "function") Module["preInit"] = [Module["preInit"]];
              while (Module["preInit"].length > 0) {
                Module["preInit"].pop()();
              }
            }
            var shouldRunNow = true;
            if (Module["noInitialRun"]) shouldRunNow = false;
            run();
            const C = Module;
            const INTERNAL = {};
            const SIZE_OF_INT = 4;
            const SIZE_OF_CURSOR = 4 * SIZE_OF_INT;
            const SIZE_OF_NODE = 5 * SIZE_OF_INT;
            const SIZE_OF_POINT = 2 * SIZE_OF_INT;
            const SIZE_OF_RANGE = 2 * SIZE_OF_INT + 2 * SIZE_OF_POINT;
            const ZERO_POINT = {
              row: 0,
              column: 0
            };
            const QUERY_WORD_REGEX = /[\w-.]*/g;
            const PREDICATE_STEP_TYPE_CAPTURE = 1;
            const PREDICATE_STEP_TYPE_STRING = 2;
            const LANGUAGE_FUNCTION_REGEX = /^_?tree_sitter_\w+/;
            let VERSION;
            let MIN_COMPATIBLE_VERSION;
            let TRANSFER_BUFFER;
            let currentParseCallback;
            let currentLogCallback;
            class ParserImpl {
              static init() {
                TRANSFER_BUFFER = C._ts_init();
                VERSION = getValue(TRANSFER_BUFFER, "i32");
                MIN_COMPATIBLE_VERSION = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
              }
              initialize() {
                C._ts_parser_new_wasm();
                this[0] = getValue(TRANSFER_BUFFER, "i32");
                this[1] = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
              }
              delete() {
                C._ts_parser_delete(this[0]);
                C._free(this[1]);
                this[0] = 0;
                this[1] = 0;
              }
              setLanguage(language) {
                let address;
                if (!language) {
                  address = 0;
                  language = null;
                } else if (language.constructor === Language) {
                  address = language[0];
                  const version = C._ts_language_version(address);
                  if (version < MIN_COMPATIBLE_VERSION || VERSION < version) {
                    throw new Error(`Incompatible language version ${version}. Compatibility range ${MIN_COMPATIBLE_VERSION} through ${VERSION}.`);
                  }
                } else {
                  throw new Error("Argument must be a Language");
                }
                this.language = language;
                C._ts_parser_set_language(this[0], address);
                return this;
              }
              getLanguage() {
                return this.language;
              }
              parse(callback, oldTree, options) {
                if (typeof callback === "string") {
                  currentParseCallback = (index, _) => callback.slice(index);
                } else if (typeof callback === "function") {
                  currentParseCallback = callback;
                } else {
                  throw new Error("Argument must be a string or a function");
                }
                if (this.logCallback) {
                  currentLogCallback = this.logCallback;
                  C._ts_parser_enable_logger_wasm(this[0], 1);
                } else {
                  currentLogCallback = null;
                  C._ts_parser_enable_logger_wasm(this[0], 0);
                }
                let rangeCount = 0;
                let rangeAddress = 0;
                if (options?.includedRanges) {
                  rangeCount = options.includedRanges.length;
                  rangeAddress = C._calloc(rangeCount, SIZE_OF_RANGE);
                  let address = rangeAddress;
                  for (let i2 = 0; i2 < rangeCount; i2++) {
                    marshalRange(address, options.includedRanges[i2]);
                    address += SIZE_OF_RANGE;
                  }
                }
                const treeAddress = C._ts_parser_parse_wasm(this[0], this[1], oldTree ? oldTree[0] : 0, rangeAddress, rangeCount);
                if (!treeAddress) {
                  currentParseCallback = null;
                  currentLogCallback = null;
                  throw new Error("Parsing failed");
                }
                const result = new Tree(INTERNAL, treeAddress, this.language, currentParseCallback);
                currentParseCallback = null;
                currentLogCallback = null;
                return result;
              }
              reset() {
                C._ts_parser_reset(this[0]);
              }
              getIncludedRanges() {
                C._ts_parser_included_ranges_wasm(this[0]);
                const count = getValue(TRANSFER_BUFFER, "i32");
                const buffer = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const result = new Array(count);
                if (count > 0) {
                  let address = buffer;
                  for (let i2 = 0; i2 < count; i2++) {
                    result[i2] = unmarshalRange(address);
                    address += SIZE_OF_RANGE;
                  }
                  C._free(buffer);
                }
                return result;
              }
              getTimeoutMicros() {
                return C._ts_parser_timeout_micros(this[0]);
              }
              setTimeoutMicros(timeout) {
                C._ts_parser_set_timeout_micros(this[0], timeout);
              }
              setLogger(callback) {
                if (!callback) {
                  callback = null;
                } else if (typeof callback !== "function") {
                  throw new Error("Logger callback must be a function");
                }
                this.logCallback = callback;
                return this;
              }
              getLogger() {
                return this.logCallback;
              }
            }
            class Tree {
              constructor(internal, address, language, textCallback) {
                assertInternal(internal);
                this[0] = address;
                this.language = language;
                this.textCallback = textCallback;
              }
              copy() {
                const address = C._ts_tree_copy(this[0]);
                return new Tree(INTERNAL, address, this.language, this.textCallback);
              }
              delete() {
                C._ts_tree_delete(this[0]);
                this[0] = 0;
              }
              edit(edit) {
                marshalEdit(edit);
                C._ts_tree_edit_wasm(this[0]);
              }
              get rootNode() {
                C._ts_tree_root_node_wasm(this[0]);
                return unmarshalNode(this);
              }
              rootNodeWithOffset(offsetBytes, offsetExtent) {
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                setValue(address, offsetBytes, "i32");
                marshalPoint(address + SIZE_OF_INT, offsetExtent);
                C._ts_tree_root_node_with_offset_wasm(this[0]);
                return unmarshalNode(this);
              }
              getLanguage() {
                return this.language;
              }
              walk() {
                return this.rootNode.walk();
              }
              getChangedRanges(other) {
                if (other.constructor !== Tree) {
                  throw new TypeError("Argument must be a Tree");
                }
                C._ts_tree_get_changed_ranges_wasm(this[0], other[0]);
                const count = getValue(TRANSFER_BUFFER, "i32");
                const buffer = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const result = new Array(count);
                if (count > 0) {
                  let address = buffer;
                  for (let i2 = 0; i2 < count; i2++) {
                    result[i2] = unmarshalRange(address);
                    address += SIZE_OF_RANGE;
                  }
                  C._free(buffer);
                }
                return result;
              }
              getIncludedRanges() {
                C._ts_tree_included_ranges_wasm(this[0]);
                const count = getValue(TRANSFER_BUFFER, "i32");
                const buffer = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const result = new Array(count);
                if (count > 0) {
                  let address = buffer;
                  for (let i2 = 0; i2 < count; i2++) {
                    result[i2] = unmarshalRange(address);
                    address += SIZE_OF_RANGE;
                  }
                  C._free(buffer);
                }
                return result;
              }
            }
            class Node {
              constructor(internal, tree) {
                assertInternal(internal);
                this.tree = tree;
              }
              get typeId() {
                marshalNode(this);
                return C._ts_node_symbol_wasm(this.tree[0]);
              }
              get grammarId() {
                marshalNode(this);
                return C._ts_node_grammar_symbol_wasm(this.tree[0]);
              }
              get type() {
                return this.tree.language.types[this.typeId] || "ERROR";
              }
              get grammarType() {
                return this.tree.language.types[this.grammarId] || "ERROR";
              }
              get endPosition() {
                marshalNode(this);
                C._ts_node_end_point_wasm(this.tree[0]);
                return unmarshalPoint(TRANSFER_BUFFER);
              }
              get endIndex() {
                marshalNode(this);
                return C._ts_node_end_index_wasm(this.tree[0]);
              }
              get text() {
                return getText(this.tree, this.startIndex, this.endIndex);
              }
              get parseState() {
                marshalNode(this);
                return C._ts_node_parse_state_wasm(this.tree[0]);
              }
              get nextParseState() {
                marshalNode(this);
                return C._ts_node_next_parse_state_wasm(this.tree[0]);
              }
              get isNamed() {
                marshalNode(this);
                return C._ts_node_is_named_wasm(this.tree[0]) === 1;
              }
              get hasError() {
                marshalNode(this);
                return C._ts_node_has_error_wasm(this.tree[0]) === 1;
              }
              get hasChanges() {
                marshalNode(this);
                return C._ts_node_has_changes_wasm(this.tree[0]) === 1;
              }
              get isError() {
                marshalNode(this);
                return C._ts_node_is_error_wasm(this.tree[0]) === 1;
              }
              get isMissing() {
                marshalNode(this);
                return C._ts_node_is_missing_wasm(this.tree[0]) === 1;
              }
              get isExtra() {
                marshalNode(this);
                return C._ts_node_is_extra_wasm(this.tree[0]) === 1;
              }
              equals(other) {
                return this.id === other.id;
              }
              child(index) {
                marshalNode(this);
                C._ts_node_child_wasm(this.tree[0], index);
                return unmarshalNode(this.tree);
              }
              namedChild(index) {
                marshalNode(this);
                C._ts_node_named_child_wasm(this.tree[0], index);
                return unmarshalNode(this.tree);
              }
              childForFieldId(fieldId) {
                marshalNode(this);
                C._ts_node_child_by_field_id_wasm(this.tree[0], fieldId);
                return unmarshalNode(this.tree);
              }
              childForFieldName(fieldName) {
                const fieldId = this.tree.language.fields.indexOf(fieldName);
                if (fieldId !== -1) return this.childForFieldId(fieldId);
                return null;
              }
              fieldNameForChild(index) {
                marshalNode(this);
                const address = C._ts_node_field_name_for_child_wasm(this.tree[0], index);
                if (!address) {
                  return null;
                }
                const result = AsciiToString(address);
                return result;
              }
              childrenForFieldName(fieldName) {
                const fieldId = this.tree.language.fields.indexOf(fieldName);
                if (fieldId !== -1 && fieldId !== 0) return this.childrenForFieldId(fieldId);
                return [];
              }
              childrenForFieldId(fieldId) {
                marshalNode(this);
                C._ts_node_children_by_field_id_wasm(this.tree[0], fieldId);
                const count = getValue(TRANSFER_BUFFER, "i32");
                const buffer = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const result = new Array(count);
                if (count > 0) {
                  let address = buffer;
                  for (let i2 = 0; i2 < count; i2++) {
                    result[i2] = unmarshalNode(this.tree, address);
                    address += SIZE_OF_NODE;
                  }
                  C._free(buffer);
                }
                return result;
              }
              firstChildForIndex(index) {
                marshalNode(this);
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                setValue(address, index, "i32");
                C._ts_node_first_child_for_byte_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              firstNamedChildForIndex(index) {
                marshalNode(this);
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                setValue(address, index, "i32");
                C._ts_node_first_named_child_for_byte_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              get childCount() {
                marshalNode(this);
                return C._ts_node_child_count_wasm(this.tree[0]);
              }
              get namedChildCount() {
                marshalNode(this);
                return C._ts_node_named_child_count_wasm(this.tree[0]);
              }
              get firstChild() {
                return this.child(0);
              }
              get firstNamedChild() {
                return this.namedChild(0);
              }
              get lastChild() {
                return this.child(this.childCount - 1);
              }
              get lastNamedChild() {
                return this.namedChild(this.namedChildCount - 1);
              }
              get children() {
                if (!this._children) {
                  marshalNode(this);
                  C._ts_node_children_wasm(this.tree[0]);
                  const count = getValue(TRANSFER_BUFFER, "i32");
                  const buffer = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                  this._children = new Array(count);
                  if (count > 0) {
                    let address = buffer;
                    for (let i2 = 0; i2 < count; i2++) {
                      this._children[i2] = unmarshalNode(this.tree, address);
                      address += SIZE_OF_NODE;
                    }
                    C._free(buffer);
                  }
                }
                return this._children;
              }
              get namedChildren() {
                if (!this._namedChildren) {
                  marshalNode(this);
                  C._ts_node_named_children_wasm(this.tree[0]);
                  const count = getValue(TRANSFER_BUFFER, "i32");
                  const buffer = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                  this._namedChildren = new Array(count);
                  if (count > 0) {
                    let address = buffer;
                    for (let i2 = 0; i2 < count; i2++) {
                      this._namedChildren[i2] = unmarshalNode(this.tree, address);
                      address += SIZE_OF_NODE;
                    }
                    C._free(buffer);
                  }
                }
                return this._namedChildren;
              }
              descendantsOfType(types, startPosition, endPosition) {
                if (!Array.isArray(types)) types = [types];
                if (!startPosition) startPosition = ZERO_POINT;
                if (!endPosition) endPosition = ZERO_POINT;
                const symbols = [];
                const typesBySymbol = this.tree.language.types;
                for (let i2 = 0, n = typesBySymbol.length; i2 < n; i2++) {
                  if (types.includes(typesBySymbol[i2])) {
                    symbols.push(i2);
                  }
                }
                const symbolsAddress = C._malloc(SIZE_OF_INT * symbols.length);
                for (let i2 = 0, n = symbols.length; i2 < n; i2++) {
                  setValue(symbolsAddress + i2 * SIZE_OF_INT, symbols[i2], "i32");
                }
                marshalNode(this);
                C._ts_node_descendants_of_type_wasm(this.tree[0], symbolsAddress, symbols.length, startPosition.row, startPosition.column, endPosition.row, endPosition.column);
                const descendantCount = getValue(TRANSFER_BUFFER, "i32");
                const descendantAddress = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const result = new Array(descendantCount);
                if (descendantCount > 0) {
                  let address = descendantAddress;
                  for (let i2 = 0; i2 < descendantCount; i2++) {
                    result[i2] = unmarshalNode(this.tree, address);
                    address += SIZE_OF_NODE;
                  }
                }
                C._free(descendantAddress);
                C._free(symbolsAddress);
                return result;
              }
              get nextSibling() {
                marshalNode(this);
                C._ts_node_next_sibling_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              get previousSibling() {
                marshalNode(this);
                C._ts_node_prev_sibling_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              get nextNamedSibling() {
                marshalNode(this);
                C._ts_node_next_named_sibling_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              get previousNamedSibling() {
                marshalNode(this);
                C._ts_node_prev_named_sibling_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              get descendantCount() {
                marshalNode(this);
                return C._ts_node_descendant_count_wasm(this.tree[0]);
              }
              get parent() {
                marshalNode(this);
                C._ts_node_parent_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              descendantForIndex(start2, end = start2) {
                if (typeof start2 !== "number" || typeof end !== "number") {
                  throw new Error("Arguments must be numbers");
                }
                marshalNode(this);
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                setValue(address, start2, "i32");
                setValue(address + SIZE_OF_INT, end, "i32");
                C._ts_node_descendant_for_index_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              namedDescendantForIndex(start2, end = start2) {
                if (typeof start2 !== "number" || typeof end !== "number") {
                  throw new Error("Arguments must be numbers");
                }
                marshalNode(this);
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                setValue(address, start2, "i32");
                setValue(address + SIZE_OF_INT, end, "i32");
                C._ts_node_named_descendant_for_index_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              descendantForPosition(start2, end = start2) {
                if (!isPoint(start2) || !isPoint(end)) {
                  throw new Error("Arguments must be {row, column} objects");
                }
                marshalNode(this);
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                marshalPoint(address, start2);
                marshalPoint(address + SIZE_OF_POINT, end);
                C._ts_node_descendant_for_position_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              namedDescendantForPosition(start2, end = start2) {
                if (!isPoint(start2) || !isPoint(end)) {
                  throw new Error("Arguments must be {row, column} objects");
                }
                marshalNode(this);
                const address = TRANSFER_BUFFER + SIZE_OF_NODE;
                marshalPoint(address, start2);
                marshalPoint(address + SIZE_OF_POINT, end);
                C._ts_node_named_descendant_for_position_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              walk() {
                marshalNode(this);
                C._ts_tree_cursor_new_wasm(this.tree[0]);
                return new TreeCursor(INTERNAL, this.tree);
              }
              toString() {
                marshalNode(this);
                const address = C._ts_node_to_string_wasm(this.tree[0]);
                const result = AsciiToString(address);
                C._free(address);
                return result;
              }
            }
            class TreeCursor {
              constructor(internal, tree) {
                assertInternal(internal);
                this.tree = tree;
                unmarshalTreeCursor(this);
              }
              delete() {
                marshalTreeCursor(this);
                C._ts_tree_cursor_delete_wasm(this.tree[0]);
                this[0] = this[1] = this[2] = 0;
              }
              reset(node) {
                marshalNode(node);
                marshalTreeCursor(this, TRANSFER_BUFFER + SIZE_OF_NODE);
                C._ts_tree_cursor_reset_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
              }
              resetTo(cursor) {
                marshalTreeCursor(this, TRANSFER_BUFFER);
                marshalTreeCursor(cursor, TRANSFER_BUFFER + SIZE_OF_CURSOR);
                C._ts_tree_cursor_reset_to_wasm(this.tree[0], cursor.tree[0]);
                unmarshalTreeCursor(this);
              }
              get nodeType() {
                return this.tree.language.types[this.nodeTypeId] || "ERROR";
              }
              get nodeTypeId() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_node_type_id_wasm(this.tree[0]);
              }
              get nodeStateId() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_node_state_id_wasm(this.tree[0]);
              }
              get nodeId() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_node_id_wasm(this.tree[0]);
              }
              get nodeIsNamed() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_node_is_named_wasm(this.tree[0]) === 1;
              }
              get nodeIsMissing() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_node_is_missing_wasm(this.tree[0]) === 1;
              }
              get nodeText() {
                marshalTreeCursor(this);
                const startIndex = C._ts_tree_cursor_start_index_wasm(this.tree[0]);
                const endIndex = C._ts_tree_cursor_end_index_wasm(this.tree[0]);
                return getText(this.tree, startIndex, endIndex);
              }
              get startPosition() {
                marshalTreeCursor(this);
                C._ts_tree_cursor_start_position_wasm(this.tree[0]);
                return unmarshalPoint(TRANSFER_BUFFER);
              }
              get endPosition() {
                marshalTreeCursor(this);
                C._ts_tree_cursor_end_position_wasm(this.tree[0]);
                return unmarshalPoint(TRANSFER_BUFFER);
              }
              get startIndex() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_start_index_wasm(this.tree[0]);
              }
              get endIndex() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_end_index_wasm(this.tree[0]);
              }
              get currentNode() {
                marshalTreeCursor(this);
                C._ts_tree_cursor_current_node_wasm(this.tree[0]);
                return unmarshalNode(this.tree);
              }
              get currentFieldId() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_field_id_wasm(this.tree[0]);
              }
              get currentFieldName() {
                return this.tree.language.fields[this.currentFieldId];
              }
              get currentDepth() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_depth_wasm(this.tree[0]);
              }
              get currentDescendantIndex() {
                marshalTreeCursor(this);
                return C._ts_tree_cursor_current_descendant_index_wasm(this.tree[0]);
              }
              gotoFirstChild() {
                marshalTreeCursor(this);
                const result = C._ts_tree_cursor_goto_first_child_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
              gotoLastChild() {
                marshalTreeCursor(this);
                const result = C._ts_tree_cursor_goto_last_child_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
              gotoFirstChildForIndex(goalIndex) {
                marshalTreeCursor(this);
                setValue(TRANSFER_BUFFER + SIZE_OF_CURSOR, goalIndex, "i32");
                const result = C._ts_tree_cursor_goto_first_child_for_index_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
              gotoFirstChildForPosition(goalPosition) {
                marshalTreeCursor(this);
                marshalPoint(TRANSFER_BUFFER + SIZE_OF_CURSOR, goalPosition);
                const result = C._ts_tree_cursor_goto_first_child_for_position_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
              gotoNextSibling() {
                marshalTreeCursor(this);
                const result = C._ts_tree_cursor_goto_next_sibling_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
              gotoPreviousSibling() {
                marshalTreeCursor(this);
                const result = C._ts_tree_cursor_goto_previous_sibling_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
              gotoDescendant(goalDescendantindex) {
                marshalTreeCursor(this);
                C._ts_tree_cursor_goto_descendant_wasm(this.tree[0], goalDescendantindex);
                unmarshalTreeCursor(this);
              }
              gotoParent() {
                marshalTreeCursor(this);
                const result = C._ts_tree_cursor_goto_parent_wasm(this.tree[0]);
                unmarshalTreeCursor(this);
                return result === 1;
              }
            }
            class Language {
              constructor(internal, address) {
                assertInternal(internal);
                this[0] = address;
                this.types = new Array(C._ts_language_symbol_count(this[0]));
                for (let i2 = 0, n = this.types.length; i2 < n; i2++) {
                  if (C._ts_language_symbol_type(this[0], i2) < 2) {
                    this.types[i2] = UTF8ToString(C._ts_language_symbol_name(this[0], i2));
                  }
                }
                this.fields = new Array(C._ts_language_field_count(this[0]) + 1);
                for (let i2 = 0, n = this.fields.length; i2 < n; i2++) {
                  const fieldName = C._ts_language_field_name_for_id(this[0], i2);
                  if (fieldName !== 0) {
                    this.fields[i2] = UTF8ToString(fieldName);
                  } else {
                    this.fields[i2] = null;
                  }
                }
              }
              get version() {
                return C._ts_language_version(this[0]);
              }
              get fieldCount() {
                return this.fields.length - 1;
              }
              get stateCount() {
                return C._ts_language_state_count(this[0]);
              }
              fieldIdForName(fieldName) {
                const result = this.fields.indexOf(fieldName);
                if (result !== -1) {
                  return result;
                } else {
                  return null;
                }
              }
              fieldNameForId(fieldId) {
                return this.fields[fieldId] || null;
              }
              idForNodeType(type, named) {
                const typeLength = lengthBytesUTF8(type);
                const typeAddress = C._malloc(typeLength + 1);
                stringToUTF8(type, typeAddress, typeLength + 1);
                const result = C._ts_language_symbol_for_name(this[0], typeAddress, typeLength, named);
                C._free(typeAddress);
                return result || null;
              }
              get nodeTypeCount() {
                return C._ts_language_symbol_count(this[0]);
              }
              nodeTypeForId(typeId) {
                const name2 = C._ts_language_symbol_name(this[0], typeId);
                return name2 ? UTF8ToString(name2) : null;
              }
              nodeTypeIsNamed(typeId) {
                return C._ts_language_type_is_named_wasm(this[0], typeId) ? true : false;
              }
              nodeTypeIsVisible(typeId) {
                return C._ts_language_type_is_visible_wasm(this[0], typeId) ? true : false;
              }
              nextState(stateId, typeId) {
                return C._ts_language_next_state(this[0], stateId, typeId);
              }
              lookaheadIterator(stateId) {
                const address = C._ts_lookahead_iterator_new(this[0], stateId);
                if (address) return new LookaheadIterable(INTERNAL, address, this);
                return null;
              }
              query(source) {
                const sourceLength = lengthBytesUTF8(source);
                const sourceAddress = C._malloc(sourceLength + 1);
                stringToUTF8(source, sourceAddress, sourceLength + 1);
                const address = C._ts_query_new(this[0], sourceAddress, sourceLength, TRANSFER_BUFFER, TRANSFER_BUFFER + SIZE_OF_INT);
                if (!address) {
                  const errorId = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                  const errorByte = getValue(TRANSFER_BUFFER, "i32");
                  const errorIndex = UTF8ToString(sourceAddress, errorByte).length;
                  const suffix = source.substr(errorIndex, 100).split("\n")[0];
                  let word = suffix.match(QUERY_WORD_REGEX)[0];
                  let error;
                  switch (errorId) {
                    case 2:
                      error = new RangeError(`Bad node name '${word}'`);
                      break;
                    case 3:
                      error = new RangeError(`Bad field name '${word}'`);
                      break;
                    case 4:
                      error = new RangeError(`Bad capture name @${word}`);
                      break;
                    case 5:
                      error = new TypeError(`Bad pattern structure at offset ${errorIndex}: '${suffix}'...`);
                      word = "";
                      break;
                    default:
                      error = new SyntaxError(`Bad syntax at offset ${errorIndex}: '${suffix}'...`);
                      word = "";
                      break;
                  }
                  error.index = errorIndex;
                  error.length = word.length;
                  C._free(sourceAddress);
                  throw error;
                }
                const stringCount = C._ts_query_string_count(address);
                const captureCount = C._ts_query_capture_count(address);
                const patternCount = C._ts_query_pattern_count(address);
                const captureNames = new Array(captureCount);
                const stringValues = new Array(stringCount);
                for (let i2 = 0; i2 < captureCount; i2++) {
                  const nameAddress = C._ts_query_capture_name_for_id(address, i2, TRANSFER_BUFFER);
                  const nameLength = getValue(TRANSFER_BUFFER, "i32");
                  captureNames[i2] = UTF8ToString(nameAddress, nameLength);
                }
                for (let i2 = 0; i2 < stringCount; i2++) {
                  const valueAddress = C._ts_query_string_value_for_id(address, i2, TRANSFER_BUFFER);
                  const nameLength = getValue(TRANSFER_BUFFER, "i32");
                  stringValues[i2] = UTF8ToString(valueAddress, nameLength);
                }
                const setProperties = new Array(patternCount);
                const assertedProperties = new Array(patternCount);
                const refutedProperties = new Array(patternCount);
                const predicates = new Array(patternCount);
                const textPredicates = new Array(patternCount);
                for (let i2 = 0; i2 < patternCount; i2++) {
                  const predicatesAddress = C._ts_query_predicates_for_pattern(address, i2, TRANSFER_BUFFER);
                  const stepCount = getValue(TRANSFER_BUFFER, "i32");
                  predicates[i2] = [];
                  textPredicates[i2] = [];
                  const steps = [];
                  let stepAddress = predicatesAddress;
                  for (let j = 0; j < stepCount; j++) {
                    const stepType = getValue(stepAddress, "i32");
                    stepAddress += SIZE_OF_INT;
                    const stepValueId = getValue(stepAddress, "i32");
                    stepAddress += SIZE_OF_INT;
                    if (stepType === PREDICATE_STEP_TYPE_CAPTURE) {
                      steps.push({
                        type: "capture",
                        name: captureNames[stepValueId]
                      });
                    } else if (stepType === PREDICATE_STEP_TYPE_STRING) {
                      steps.push({
                        type: "string",
                        value: stringValues[stepValueId]
                      });
                    } else if (steps.length > 0) {
                      if (steps[0].type !== "string") {
                        throw new Error("Predicates must begin with a literal value");
                      }
                      const operator = steps[0].value;
                      let isPositive = true;
                      let matchAll = true;
                      let captureName;
                      switch (operator) {
                        case "any-not-eq?":
                        case "not-eq?":
                          isPositive = false;
                        case "any-eq?":
                        case "eq?":
                          if (steps.length !== 3) {
                            throw new Error(`Wrong number of arguments to \`#${operator}\` predicate. Expected 2, got ${steps.length - 1}`);
                          }
                          if (steps[1].type !== "capture") {
                            throw new Error(`First argument of \`#${operator}\` predicate must be a capture. Got "${steps[1].value}"`);
                          }
                          matchAll = !operator.startsWith("any-");
                          if (steps[2].type === "capture") {
                            const captureName1 = steps[1].name;
                            const captureName2 = steps[2].name;
                            textPredicates[i2].push((captures) => {
                              const nodes1 = [];
                              const nodes2 = [];
                              for (const c of captures) {
                                if (c.name === captureName1) nodes1.push(c.node);
                                if (c.name === captureName2) nodes2.push(c.node);
                              }
                              const compare = (n1, n2, positive) => positive ? n1.text === n2.text : n1.text !== n2.text;
                              return matchAll ? nodes1.every((n1) => nodes2.some((n2) => compare(n1, n2, isPositive))) : nodes1.some((n1) => nodes2.some((n2) => compare(n1, n2, isPositive)));
                            });
                          } else {
                            captureName = steps[1].name;
                            const stringValue = steps[2].value;
                            const matches = (n) => n.text === stringValue;
                            const doesNotMatch = (n) => n.text !== stringValue;
                            textPredicates[i2].push((captures) => {
                              const nodes = [];
                              for (const c of captures) {
                                if (c.name === captureName) nodes.push(c.node);
                              }
                              const test = isPositive ? matches : doesNotMatch;
                              return matchAll ? nodes.every(test) : nodes.some(test);
                            });
                          }
                          break;
                        case "any-not-match?":
                        case "not-match?":
                          isPositive = false;
                        case "any-match?":
                        case "match?":
                          if (steps.length !== 3) {
                            throw new Error(`Wrong number of arguments to \`#${operator}\` predicate. Expected 2, got ${steps.length - 1}.`);
                          }
                          if (steps[1].type !== "capture") {
                            throw new Error(`First argument of \`#${operator}\` predicate must be a capture. Got "${steps[1].value}".`);
                          }
                          if (steps[2].type !== "string") {
                            throw new Error(`Second argument of \`#${operator}\` predicate must be a string. Got @${steps[2].value}.`);
                          }
                          captureName = steps[1].name;
                          const regex = new RegExp(steps[2].value);
                          matchAll = !operator.startsWith("any-");
                          textPredicates[i2].push((captures) => {
                            const nodes = [];
                            for (const c of captures) {
                              if (c.name === captureName) nodes.push(c.node.text);
                            }
                            const test = (text, positive) => positive ? regex.test(text) : !regex.test(text);
                            if (nodes.length === 0) return !isPositive;
                            return matchAll ? nodes.every((text) => test(text, isPositive)) : nodes.some((text) => test(text, isPositive));
                          });
                          break;
                        case "set!":
                          if (steps.length < 2 || steps.length > 3) {
                            throw new Error(`Wrong number of arguments to \`#set!\` predicate. Expected 1 or 2. Got ${steps.length - 1}.`);
                          }
                          if (steps.some((s) => s.type !== "string")) {
                            throw new Error(`Arguments to \`#set!\` predicate must be a strings.".`);
                          }
                          if (!setProperties[i2]) setProperties[i2] = {};
                          setProperties[i2][steps[1].value] = steps[2] ? steps[2].value : null;
                          break;
                        case "is?":
                        case "is-not?":
                          if (steps.length < 2 || steps.length > 3) {
                            throw new Error(`Wrong number of arguments to \`#${operator}\` predicate. Expected 1 or 2. Got ${steps.length - 1}.`);
                          }
                          if (steps.some((s) => s.type !== "string")) {
                            throw new Error(`Arguments to \`#${operator}\` predicate must be a strings.".`);
                          }
                          const properties = operator === "is?" ? assertedProperties : refutedProperties;
                          if (!properties[i2]) properties[i2] = {};
                          properties[i2][steps[1].value] = steps[2] ? steps[2].value : null;
                          break;
                        case "not-any-of?":
                          isPositive = false;
                        case "any-of?":
                          if (steps.length < 2) {
                            throw new Error(`Wrong number of arguments to \`#${operator}\` predicate. Expected at least 1. Got ${steps.length - 1}.`);
                          }
                          if (steps[1].type !== "capture") {
                            throw new Error(`First argument of \`#${operator}\` predicate must be a capture. Got "${steps[1].value}".`);
                          }
                          for (let i3 = 2; i3 < steps.length; i3++) {
                            if (steps[i3].type !== "string") {
                              throw new Error(`Arguments to \`#${operator}\` predicate must be a strings.".`);
                            }
                          }
                          captureName = steps[1].name;
                          const values = steps.slice(2).map((s) => s.value);
                          textPredicates[i2].push((captures) => {
                            const nodes = [];
                            for (const c of captures) {
                              if (c.name === captureName) nodes.push(c.node.text);
                            }
                            if (nodes.length === 0) return !isPositive;
                            return nodes.every((text) => values.includes(text)) === isPositive;
                          });
                          break;
                        default:
                          predicates[i2].push({
                            operator,
                            operands: steps.slice(1)
                          });
                      }
                      steps.length = 0;
                    }
                  }
                  Object.freeze(setProperties[i2]);
                  Object.freeze(assertedProperties[i2]);
                  Object.freeze(refutedProperties[i2]);
                }
                C._free(sourceAddress);
                return new Query(INTERNAL, address, captureNames, textPredicates, predicates, Object.freeze(setProperties), Object.freeze(assertedProperties), Object.freeze(refutedProperties));
              }
              static load(input) {
                let bytes;
                if (input instanceof Uint8Array) {
                  bytes = Promise.resolve(input);
                } else {
                  const url = input;
                  if (typeof process !== "undefined" && process.versions && process.versions.node) {
                    const fs2 = require("fs");
                    bytes = Promise.resolve(fs2.readFileSync(url));
                  } else {
                    bytes = fetch(url).then((response) => response.arrayBuffer().then((buffer) => {
                      if (response.ok) {
                        return new Uint8Array(buffer);
                      } else {
                        const body2 = new TextDecoder("utf-8").decode(buffer);
                        throw new Error(`Language.load failed with status ${response.status}.

${body2}`);
                      }
                    }));
                  }
                }
                return bytes.then((bytes2) => loadWebAssemblyModule(bytes2, {
                  loadAsync: true
                })).then((mod) => {
                  const symbolNames = Object.keys(mod);
                  const functionName = symbolNames.find((key) => LANGUAGE_FUNCTION_REGEX.test(key) && !key.includes("external_scanner_"));
                  if (!functionName) {
                    console.log(`Couldn't find language function in WASM file. Symbols:
${JSON.stringify(symbolNames, null, 2)}`);
                  }
                  const languageAddress = mod[functionName]();
                  return new Language(INTERNAL, languageAddress);
                });
              }
            }
            class LookaheadIterable {
              constructor(internal, address, language) {
                assertInternal(internal);
                this[0] = address;
                this.language = language;
              }
              get currentTypeId() {
                return C._ts_lookahead_iterator_current_symbol(this[0]);
              }
              get currentType() {
                return this.language.types[this.currentTypeId] || "ERROR";
              }
              delete() {
                C._ts_lookahead_iterator_delete(this[0]);
                this[0] = 0;
              }
              resetState(stateId) {
                return C._ts_lookahead_iterator_reset_state(this[0], stateId);
              }
              reset(language, stateId) {
                if (C._ts_lookahead_iterator_reset(this[0], language[0], stateId)) {
                  this.language = language;
                  return true;
                }
                return false;
              }
              [Symbol.iterator]() {
                const self2 = this;
                return {
                  next() {
                    if (C._ts_lookahead_iterator_next(self2[0])) {
                      return {
                        done: false,
                        value: self2.currentType
                      };
                    }
                    return {
                      done: true,
                      value: ""
                    };
                  }
                };
              }
            }
            class Query {
              constructor(internal, address, captureNames, textPredicates, predicates, setProperties, assertedProperties, refutedProperties) {
                assertInternal(internal);
                this[0] = address;
                this.captureNames = captureNames;
                this.textPredicates = textPredicates;
                this.predicates = predicates;
                this.setProperties = setProperties;
                this.assertedProperties = assertedProperties;
                this.refutedProperties = refutedProperties;
                this.exceededMatchLimit = false;
              }
              delete() {
                C._ts_query_delete(this[0]);
                this[0] = 0;
              }
              matches(node, { startPosition = ZERO_POINT, endPosition = ZERO_POINT, startIndex = 0, endIndex = 0, matchLimit = 4294967295, maxStartDepth = 4294967295, timeoutMicros = 0 } = {}) {
                if (typeof matchLimit !== "number") {
                  throw new Error("Arguments must be numbers");
                }
                marshalNode(node);
                C._ts_query_matches_wasm(this[0], node.tree[0], startPosition.row, startPosition.column, endPosition.row, endPosition.column, startIndex, endIndex, matchLimit, maxStartDepth, timeoutMicros);
                const rawCount = getValue(TRANSFER_BUFFER, "i32");
                const startAddress = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const didExceedMatchLimit = getValue(TRANSFER_BUFFER + 2 * SIZE_OF_INT, "i32");
                const result = new Array(rawCount);
                this.exceededMatchLimit = Boolean(didExceedMatchLimit);
                let filteredCount = 0;
                let address = startAddress;
                for (let i2 = 0; i2 < rawCount; i2++) {
                  const pattern = getValue(address, "i32");
                  address += SIZE_OF_INT;
                  const captureCount = getValue(address, "i32");
                  address += SIZE_OF_INT;
                  const captures = new Array(captureCount);
                  address = unmarshalCaptures(this, node.tree, address, captures);
                  if (this.textPredicates[pattern].every((p) => p(captures))) {
                    result[filteredCount] = {
                      pattern,
                      captures
                    };
                    const setProperties = this.setProperties[pattern];
                    if (setProperties) result[filteredCount].setProperties = setProperties;
                    const assertedProperties = this.assertedProperties[pattern];
                    if (assertedProperties) result[filteredCount].assertedProperties = assertedProperties;
                    const refutedProperties = this.refutedProperties[pattern];
                    if (refutedProperties) result[filteredCount].refutedProperties = refutedProperties;
                    filteredCount++;
                  }
                }
                result.length = filteredCount;
                C._free(startAddress);
                return result;
              }
              captures(node, { startPosition = ZERO_POINT, endPosition = ZERO_POINT, startIndex = 0, endIndex = 0, matchLimit = 4294967295, maxStartDepth = 4294967295, timeoutMicros = 0 } = {}) {
                if (typeof matchLimit !== "number") {
                  throw new Error("Arguments must be numbers");
                }
                marshalNode(node);
                C._ts_query_captures_wasm(this[0], node.tree[0], startPosition.row, startPosition.column, endPosition.row, endPosition.column, startIndex, endIndex, matchLimit, maxStartDepth, timeoutMicros);
                const count = getValue(TRANSFER_BUFFER, "i32");
                const startAddress = getValue(TRANSFER_BUFFER + SIZE_OF_INT, "i32");
                const didExceedMatchLimit = getValue(TRANSFER_BUFFER + 2 * SIZE_OF_INT, "i32");
                const result = [];
                this.exceededMatchLimit = Boolean(didExceedMatchLimit);
                const captures = [];
                let address = startAddress;
                for (let i2 = 0; i2 < count; i2++) {
                  const pattern = getValue(address, "i32");
                  address += SIZE_OF_INT;
                  const captureCount = getValue(address, "i32");
                  address += SIZE_OF_INT;
                  const captureIndex = getValue(address, "i32");
                  address += SIZE_OF_INT;
                  captures.length = captureCount;
                  address = unmarshalCaptures(this, node.tree, address, captures);
                  if (this.textPredicates[pattern].every((p) => p(captures))) {
                    const capture = captures[captureIndex];
                    const setProperties = this.setProperties[pattern];
                    if (setProperties) capture.setProperties = setProperties;
                    const assertedProperties = this.assertedProperties[pattern];
                    if (assertedProperties) capture.assertedProperties = assertedProperties;
                    const refutedProperties = this.refutedProperties[pattern];
                    if (refutedProperties) capture.refutedProperties = refutedProperties;
                    result.push(capture);
                  }
                }
                C._free(startAddress);
                return result;
              }
              predicatesForPattern(patternIndex) {
                return this.predicates[patternIndex];
              }
              disableCapture(captureName) {
                const captureNameLength = lengthBytesUTF8(captureName);
                const captureNameAddress = C._malloc(captureNameLength + 1);
                stringToUTF8(captureName, captureNameAddress, captureNameLength + 1);
                C._ts_query_disable_capture(this[0], captureNameAddress, captureNameLength);
                C._free(captureNameAddress);
              }
              didExceedMatchLimit() {
                return this.exceededMatchLimit;
              }
            }
            function getText(tree, startIndex, endIndex) {
              const length = endIndex - startIndex;
              let result = tree.textCallback(startIndex, null, endIndex);
              startIndex += result.length;
              while (startIndex < endIndex) {
                const string = tree.textCallback(startIndex, null, endIndex);
                if (string && string.length > 0) {
                  startIndex += string.length;
                  result += string;
                } else {
                  break;
                }
              }
              if (startIndex > endIndex) {
                result = result.slice(0, length);
              }
              return result;
            }
            function unmarshalCaptures(query, tree, address, result) {
              for (let i2 = 0, n = result.length; i2 < n; i2++) {
                const captureIndex = getValue(address, "i32");
                address += SIZE_OF_INT;
                const node = unmarshalNode(tree, address);
                address += SIZE_OF_NODE;
                result[i2] = {
                  name: query.captureNames[captureIndex],
                  node
                };
              }
              return address;
            }
            function assertInternal(x) {
              if (x !== INTERNAL) throw new Error("Illegal constructor");
            }
            function isPoint(point) {
              return point && typeof point.row === "number" && typeof point.column === "number";
            }
            function marshalNode(node) {
              let address = TRANSFER_BUFFER;
              setValue(address, node.id, "i32");
              address += SIZE_OF_INT;
              setValue(address, node.startIndex, "i32");
              address += SIZE_OF_INT;
              setValue(address, node.startPosition.row, "i32");
              address += SIZE_OF_INT;
              setValue(address, node.startPosition.column, "i32");
              address += SIZE_OF_INT;
              setValue(address, node[0], "i32");
            }
            function unmarshalNode(tree, address = TRANSFER_BUFFER) {
              const id = getValue(address, "i32");
              address += SIZE_OF_INT;
              if (id === 0) return null;
              const index = getValue(address, "i32");
              address += SIZE_OF_INT;
              const row = getValue(address, "i32");
              address += SIZE_OF_INT;
              const column = getValue(address, "i32");
              address += SIZE_OF_INT;
              const other = getValue(address, "i32");
              const result = new Node(INTERNAL, tree);
              result.id = id;
              result.startIndex = index;
              result.startPosition = {
                row,
                column
              };
              result[0] = other;
              return result;
            }
            function marshalTreeCursor(cursor, address = TRANSFER_BUFFER) {
              setValue(address + 0 * SIZE_OF_INT, cursor[0], "i32");
              setValue(address + 1 * SIZE_OF_INT, cursor[1], "i32");
              setValue(address + 2 * SIZE_OF_INT, cursor[2], "i32");
              setValue(address + 3 * SIZE_OF_INT, cursor[3], "i32");
            }
            function unmarshalTreeCursor(cursor) {
              cursor[0] = getValue(TRANSFER_BUFFER + 0 * SIZE_OF_INT, "i32");
              cursor[1] = getValue(TRANSFER_BUFFER + 1 * SIZE_OF_INT, "i32");
              cursor[2] = getValue(TRANSFER_BUFFER + 2 * SIZE_OF_INT, "i32");
              cursor[3] = getValue(TRANSFER_BUFFER + 3 * SIZE_OF_INT, "i32");
            }
            function marshalPoint(address, point) {
              setValue(address, point.row, "i32");
              setValue(address + SIZE_OF_INT, point.column, "i32");
            }
            function unmarshalPoint(address) {
              const result = {
                row: getValue(address, "i32") >>> 0,
                column: getValue(address + SIZE_OF_INT, "i32") >>> 0
              };
              return result;
            }
            function marshalRange(address, range) {
              marshalPoint(address, range.startPosition);
              address += SIZE_OF_POINT;
              marshalPoint(address, range.endPosition);
              address += SIZE_OF_POINT;
              setValue(address, range.startIndex, "i32");
              address += SIZE_OF_INT;
              setValue(address, range.endIndex, "i32");
              address += SIZE_OF_INT;
            }
            function unmarshalRange(address) {
              const result = {};
              result.startPosition = unmarshalPoint(address);
              address += SIZE_OF_POINT;
              result.endPosition = unmarshalPoint(address);
              address += SIZE_OF_POINT;
              result.startIndex = getValue(address, "i32") >>> 0;
              address += SIZE_OF_INT;
              result.endIndex = getValue(address, "i32") >>> 0;
              return result;
            }
            function marshalEdit(edit) {
              let address = TRANSFER_BUFFER;
              marshalPoint(address, edit.startPosition);
              address += SIZE_OF_POINT;
              marshalPoint(address, edit.oldEndPosition);
              address += SIZE_OF_POINT;
              marshalPoint(address, edit.newEndPosition);
              address += SIZE_OF_POINT;
              setValue(address, edit.startIndex, "i32");
              address += SIZE_OF_INT;
              setValue(address, edit.oldEndIndex, "i32");
              address += SIZE_OF_INT;
              setValue(address, edit.newEndIndex, "i32");
              address += SIZE_OF_INT;
            }
            for (const name2 of Object.getOwnPropertyNames(ParserImpl.prototype)) {
              Object.defineProperty(Parser.prototype, name2, {
                value: ParserImpl.prototype[name2],
                enumerable: false,
                writable: false
              });
            }
            Parser.Language = Language;
            Module.onRuntimeInitialized = () => {
              ParserImpl.init();
              resolveInitPromise();
            };
          });
        }
      }
      return Parser;
    }();
    if (typeof exports === "object") {
      module.exports = TreeSitter;
    }
  }
});

// src/index.js
var require_index = __commonJS({
  "src/index.js"(exports2, module2) {
    "use strict";
    var fs2 = require("fs");
    var path = require("path");
    var { execFileSync } = require("child_process");
    var Parser2 = require_tree_sitter();
    var RUNNER_DIR = __dirname;
    var GRAMMAR_DIR = path.join(RUNNER_DIR, "grammars");
    var LANG_DETECT_PATH = path.join(RUNNER_DIR, "lang-detect.json");
    var GRAMMAR_WASM = {
      c_sharp: "tree-sitter-c_sharp.wasm",
      typescript: "tree-sitter-typescript.wasm",
      tsx: "tree-sitter-tsx.wasm",
      java: "tree-sitter-java.wasm",
      python: "tree-sitter-python.wasm",
      javascript: "tree-sitter-javascript.wasm"
    };
    var _initPromise = null;
    function initParser() {
      if (!_initPromise) {
        _initPromise = Parser2.init({
          locateFile: () => path.join(GRAMMAR_DIR, "tree-sitter.wasm")
        });
      }
      return _initPromise;
    }
    var _langCache = {};
    async function loadLanguage(languageId) {
      if (_langCache[languageId]) return _langCache[languageId];
      const wasm = GRAMMAR_WASM[languageId];
      if (!wasm) throw new Error(`no bundled grammar for languageId: ${languageId}`);
      const lang = await Parser2.Language.load(path.join(GRAMMAR_DIR, wasm));
      _langCache[languageId] = lang;
      return lang;
    }
    function loadLangDetect() {
      return JSON.parse(fs2.readFileSync(LANG_DETECT_PATH, "utf8"));
    }
    function detectLanguage(file) {
      const map = loadLangDetect();
      const ext = path.extname(file).toLowerCase();
      return map[ext] || "floor";
    }
    async function parseFile(absFilePath, languageId) {
      await initParser();
      const lang = await loadLanguage(languageId);
      const parser = new Parser2();
      parser.setLanguage(lang);
      const source = fs2.readFileSync(absFilePath, "utf8");
      const tree = parser.parse(source);
      return { tree, language: languageId, source };
    }
    function isBinary(absPath) {
      let fd;
      try {
        fd = fs2.openSync(absPath, "r");
        const buf = Buffer.alloc(8e3);
        const bytes = fs2.readSync(fd, buf, 0, 8e3, 0);
        for (let i2 = 0; i2 < bytes; i2++) {
          if (buf[i2] === 0) return true;
        }
        return false;
      } catch {
        return false;
      } finally {
        if (fd !== void 0) fs2.closeSync(fd);
      }
    }
    function enumerate(dir) {
      const out2 = execFileSync("rg", ["--files", "--no-require-git"], {
        cwd: dir,
        encoding: "utf8",
        maxBuffer: 64 * 1024 * 1024
      });
      return out2.split("\n").filter(Boolean).filter((rel) => !isBinary(path.join(dir, rel)));
    }
    module2.exports = {
      initParser,
      loadLanguage,
      parseFile,
      detectLanguage,
      enumerate,
      GRAMMAR_WASM,
      GRAMMAR_DIR
    };
  }
});

// src/extract-tier1.js
var require_extract_tier1 = __commonJS({
  "src/extract-tier1.js"(exports2, module2) {
    "use strict";
    var fs2 = require("fs");
    var path = require("path");
    var TAGS_DIR = path.join(__dirname, "tags");
    var OVERLOAD_LANGS = {
      c_sharp: { paramsRe: /parameter_list/, paramRe: /^parameter$/ },
      java: { paramsRe: /formal_parameters/, paramRe: /parameter/ }
    };
    var PARAM_MODIFIERS = /* @__PURE__ */ new Set(["ref", "out", "in", "params"]);
    var _queryCache = {};
    function loadQuery(lang, languageId) {
      if (_queryCache[languageId]) return _queryCache[languageId];
      const scm = fs2.readFileSync(path.join(TAGS_DIR, `${languageId}.scm`), "utf8");
      const q = lang.query(scm);
      _queryCache[languageId] = q;
      return q;
    }
    function stripWs(s) {
      return s.replace(/\s+/g, "");
    }
    function firstTypeChild(paramNode) {
      const nameNode = paramNode.childForFieldName("name");
      for (let i2 = 0; i2 < paramNode.namedChildCount; i2++) {
        const c = paramNode.namedChild(i2);
        if (nameNode && c.startIndex === nameNode.startIndex) continue;
        return c;
      }
      return null;
    }
    function renderOverload(declNode, cfg) {
      let params = null;
      for (let i2 = 0; i2 < declNode.namedChildCount; i2++) {
        const c = declNode.namedChild(i2);
        if (cfg.paramsRe.test(c.type)) {
          params = c;
          break;
        }
      }
      if (!params) return "()";
      const types = [];
      for (let i2 = 0; i2 < params.namedChildCount; i2++) {
        const p = params.namedChild(i2);
        if (!cfg.paramRe.test(p.type)) continue;
        const typeNode = p.childForFieldName("type") || firstTypeChild(p);
        const typeText = typeNode ? typeNode.text : "";
        const mods = [];
        for (let j = 0; j < p.childCount; j++) {
          const mc = p.child(j);
          if (typeNode && mc.startIndex >= typeNode.startIndex) break;
          if (PARAM_MODIFIERS.has(mc.text)) mods.push(mc.text);
        }
        const prefix = mods.length ? mods.join(" ") + " " : "";
        types.push(prefix + stripWs(typeText));
      }
      return "(" + types.join(",") + ")";
    }
    function errorAtOrBeforeName(declNode, nameNode) {
      if (!declNode.hasError && !nameNode.isMissing) return false;
      if (nameNode.isMissing || nameNode.type === "ERROR") return true;
      let found = false;
      (function walk(n) {
        if (found) return;
        if ((n.type === "ERROR" || n.isMissing) && n.startIndex <= nameNode.startIndex) {
          found = true;
          return;
        }
        for (let i2 = 0; i2 < n.childCount; i2++) walk(n.child(i2));
      })(declNode);
      return found;
    }
    function collectDefinitions(query, root) {
      const defs = [];
      const matches = query.matches(root);
      for (const m of matches) {
        let nameCap = null;
        let defCap = null;
        for (const c of m.captures) {
          if (c.name === "name") nameCap = c;
          else if (c.name.startsWith("definition.")) defCap = c;
        }
        if (!nameCap || !defCap) continue;
        defs.push({
          declNode: defCap.node,
          nameNode: nameCap.node,
          kind: defCap.name.slice("definition.".length),
          name: nameCap.node.text
        });
      }
      return defs;
    }
    function fqnFor(def, defs) {
      const ancestors = defs.filter(
        (a) => a !== def && a.declNode.startIndex <= def.declNode.startIndex && a.declNode.endIndex >= def.declNode.endIndex
      );
      ancestors.sort((a, b) => a.declNode.startIndex - b.declNode.startIndex || b.declNode.endIndex - a.declNode.endIndex);
      return [...ancestors.map((a) => a.name), def.name].join(".");
    }
    function extractTier1(relPath, languageId, lang, tree) {
      const query = loadQuery(lang, languageId);
      const defs = collectDefinitions(query, tree.rootNode);
      const overloadCfg = OVERLOAD_LANGS[languageId];
      for (const d of defs) {
        if (errorAtOrBeforeName(d.declNode, d.nameNode)) {
          return { floored: true, reason: "untrusted-name", anchors: [] };
        }
      }
      const anchors = defs.map((d) => {
        let symbolPath = fqnFor(d, defs);
        if (overloadCfg && (d.kind === "method" || d.kind === "function" || d.kind === "constructor")) {
          symbolPath += renderOverload(d.declNode, overloadCfg);
        }
        return {
          anchor: `${relPath}#${symbolPath}`,
          kind: d.kind,
          line: d.nameNode.startPosition.row + 1
        };
      });
      return { floored: false, anchors };
    }
    module2.exports = { extractTier1, errorAtOrBeforeName, renderOverload };
  }
});

// src/extract-tier2-floor.js
var require_extract_tier2_floor = __commonJS({
  "src/extract-tier2-floor.js"(exports2, module2) {
    "use strict";
    var FLAT_ALLOWLIST = /* @__PURE__ */ new Set(["shell"]);
    var SHELL_FN = /^[ \t]*(?:function[ \t]+([A-Za-z_][A-Za-z0-9_-]*)[ \t]*(?:\([ \t]*\))?|([A-Za-z_][A-Za-z0-9_-]*)[ \t]*\([ \t]*\))[ \t]*\{/;
    function extractTier2(relPath, languageId, source) {
      if (!FLAT_ALLOWLIST.has(languageId)) {
        return { anchors: [] };
      }
      const lines = source.split("\n");
      const anchors = [];
      const seen = /* @__PURE__ */ new Set();
      for (let i2 = 0; i2 < lines.length; i2++) {
        const m = SHELL_FN.exec(lines[i2]);
        if (!m) continue;
        const name2 = m[1] || m[2];
        if (name2 && !seen.has(name2)) {
          seen.add(name2);
          anchors.push({ anchor: `${relPath}#${name2}`, kind: "function", line: i2 + 1 });
        }
      }
      return { anchors };
    }
    module2.exports = { extractTier2, FLAT_ALLOWLIST };
  }
});

// src/extract-tier3-md.js
var require_extract_tier3_md = __commonJS({
  "src/extract-tier3-md.js"(exports2, module2) {
    "use strict";
    function slugify(text) {
      let s = text.replace(/[^A-Za-z0-9 -]/g, "");
      s = s.toLowerCase();
      s = s.replace(/ /g, "-");
      s = s.replace(/-+/g, "-");
      s = s.replace(/^-+|-+$/g, "");
      return s;
    }
    function extractTier3(relPath, source) {
      const lines = source.split("\n");
      const stack = [];
      const seen = /* @__PURE__ */ new Map();
      const anchors = [];
      let headingOrdinal = 0;
      for (let i2 = 0; i2 < lines.length; i2++) {
        const m = /^(#{1,6})[ \t]+(.*\S)[ \t]*$/.exec(lines[i2]);
        if (!m) continue;
        const level = m[1].length;
        headingOrdinal++;
        let slug = slugify(m[2]);
        if (!slug) slug = `section-${headingOrdinal}`;
        while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
        let full = [...stack.map((e) => e.slug), slug].join("/");
        const n = seen.get(full) || 0;
        seen.set(full, n + 1);
        if (n > 0) full = `${full}-${n}`;
        anchors.push({ anchor: `${relPath}#${full}`, kind: "heading", line: i2 + 1 });
        stack.push({ level, slug });
      }
      return { anchors };
    }
    module2.exports = { extractTier3, slugify };
  }
});

// src/extract.js
var require_extract = __commonJS({
  "src/extract.js"(exports2, module2) {
    "use strict";
    var fs2 = require("fs");
    var path = require("path");
    var { initParser, loadLanguage, parseFile, detectLanguage, GRAMMAR_WASM } = require_index();
    var { extractTier1 } = require_extract_tier1();
    var { extractTier2, FLAT_ALLOWLIST } = require_extract_tier2_floor();
    var { extractTier3 } = require_extract_tier3_md();
    function toRel(absFilePath, root) {
      const base = root || process.cwd();
      return path.relative(base, absFilePath).split(path.sep).join("/");
    }
    async function extract2(absFilePath, root) {
      const abs = path.resolve(absFilePath);
      const relPath = toRel(abs, root);
      const languageId = detectLanguage(abs);
      if (GRAMMAR_WASM[languageId]) {
        await initParser();
        const lang = await loadLanguage(languageId);
        const { tree } = await parseFile(abs, languageId);
        const r2 = extractTier1(relPath, languageId, lang, tree);
        if (r2.floored) {
          return { file: relPath, language: languageId, tier: "floor", floored: true, reason: r2.reason, anchors: [] };
        }
        return { file: relPath, language: languageId, tier: "grammar", floored: false, anchors: r2.anchors };
      }
      if (languageId === "markdown") {
        const source2 = fs2.readFileSync(abs, "utf8");
        return { file: relPath, language: languageId, tier: "markdown", floored: false, anchors: extractTier3(relPath, source2).anchors };
      }
      const source = fs2.readFileSync(abs, "utf8");
      const r = extractTier2(relPath, languageId, source);
      return {
        file: relPath,
        language: languageId,
        tier: FLAT_ALLOWLIST.has(languageId) ? "floor-flat" : "floor",
        floored: false,
        anchors: r.anchors
      };
    }
    module2.exports = { extract: extract2 };
  }
});

// src/rank.js
var require_rank = __commonJS({
  "src/rank.js"(exports2, module2) {
    "use strict";
    function leafName(symbolPath) {
      if (!symbolPath) return "";
      const noOverload = symbolPath.replace(/\(.*\)$/, "");
      return noOverload.split(/[./]/).pop();
    }
    function escapeRe(s) {
      return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function rankDefinitions(perFile) {
      const corpus = perFile.map((f) => f.source).join("\n");
      const counts = {};
      function refCount(name2) {
        if (!name2) return 0;
        if (name2 in counts) return counts[name2];
        const m = corpus.match(new RegExp("\\b" + escapeRe(name2) + "\\b", "g"));
        counts[name2] = m ? m.length : 0;
        return counts[name2];
      }
      const defs = [];
      for (const f of perFile) {
        for (const a of f.result.anchors) {
          const symbolPath = a.anchor.includes("#") ? a.anchor.slice(a.anchor.indexOf("#") + 1) : "";
          const name2 = leafName(symbolPath);
          defs.push({
            rel: f.rel,
            anchor: a.anchor,
            kind: a.kind,
            line: a.line,
            // discount the definition's own occurrence so a never-referenced symbol scores 0
            score: Math.max(0, refCount(name2) - 1)
          });
        }
      }
      defs.sort((a, b) => b.score - a.score || a.rel.localeCompare(b.rel) || a.line - b.line);
      return defs;
    }
    module2.exports = { rankDefinitions, leafName };
  }
});

// src/budget-trim.js
var require_budget_trim = __commonJS({
  "src/budget-trim.js"(exports2, module2) {
    "use strict";
    function estimateTokens(text) {
      return Math.ceil(text.length / 4);
    }
    function trimToBudget(orderedDefs, renderFn, budget) {
      if (estimateTokens(renderFn(orderedDefs)) <= budget) return orderedDefs.slice();
      let lo = 0;
      let hi = orderedDefs.length;
      let best = 0;
      while (lo <= hi) {
        const mid = lo + hi >> 1;
        const tokens = estimateTokens(renderFn(orderedDefs.slice(0, mid)));
        if (tokens <= budget) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return orderedDefs.slice(0, best);
    }
    module2.exports = { trimToBudget, estimateTokens };
  }
});

// src/assemble-area.js
var require_assemble_area = __commonJS({
  "src/assemble-area.js"(exports2, module2) {
    "use strict";
    var fs2 = require("fs");
    var path = require("path");
    var crypto = require("crypto");
    var { execFileSync } = require("child_process");
    var { enumerate } = require_index();
    var { extract: extract2 } = require_extract();
    var { rankDefinitions } = require_rank();
    var { trimToBudget, estimateTokens } = require_budget_trim();
    var DEFAULT_BUDGET = 4096;
    function mapDir(root) {
      return path.join(root, ".craft", "map");
    }
    function indexPath(root) {
      return path.join(mapDir(root), "index.json");
    }
    function readIndex(root) {
      try {
        return JSON.parse(fs2.readFileSync(indexPath(root), "utf8"));
      } catch {
        return { version: 1, areas: {} };
      }
    }
    function writeIndex(root, index) {
      fs2.mkdirSync(mapDir(root), { recursive: true });
      fs2.writeFileSync(indexPath(root), JSON.stringify(index, null, 2) + "\n");
    }
    function headSha(root) {
      try {
        return execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
      } catch {
        return null;
      }
    }
    function isEnabled(root) {
      let text;
      try {
        text = fs2.readFileSync(path.join(root, ".craft", "settings.yaml"), "utf8");
      } catch {
        return true;
      }
      let inMap = false;
      for (const line of text.split("\n")) {
        if (/^map:\s*$/.test(line)) {
          inMap = true;
          continue;
        }
        if (/^\S/.test(line)) inMap = false;
        if (inMap && /^\s+enabled:\s*false\b/.test(line)) return false;
      }
      return true;
    }
    function getBudget(root) {
      try {
        const text = fs2.readFileSync(path.join(root, ".craft", "settings.yaml"), "utf8");
        const m = text.match(/token_budget:\s*(\d+)/);
        if (m) return parseInt(m[1], 10);
      } catch {
      }
      return DEFAULT_BUDGET;
    }
    function sepForTier(tier) {
      return tier === "markdown" ? "/" : ".";
    }
    function splitSegments(symbolPath, sep) {
      let overload = "";
      const p = symbolPath.indexOf("(");
      if (p !== -1) {
        overload = symbolPath.slice(p);
        symbolPath = symbolPath.slice(0, p);
      }
      const segs = symbolPath.length ? symbolPath.split(sep) : [];
      if (segs.length) segs[segs.length - 1] += overload;
      return segs;
    }
    function renderSlice(defs, fileMeta) {
      const byFile = /* @__PURE__ */ new Map();
      defs.forEach((d, i2) => {
        if (!byFile.has(d.rel)) byFile.set(d.rel, { defs: [], firstRank: i2 });
        byFile.get(d.rel).defs.push(d);
      });
      const files = [...byFile.entries()].sort((a, b) => a[1].firstRank - b[1].firstRank);
      const lines = [];
      for (const [rel, grp] of files) {
        const meta = fileMeta.get(rel) || { tier: "grammar" };
        const sep = sepForTier(meta.tier);
        lines.push(rel);
        const tree = /* @__PURE__ */ new Map();
        const sourceOrder = grp.defs.slice().sort((a, b) => a.line - b.line);
        for (const d of sourceOrder) {
          const symbolPath = d.anchor.slice(d.anchor.indexOf("#") + 1);
          let node = tree;
          for (const seg of splitSegments(symbolPath, sep)) {
            if (!node.has(seg)) node.set(seg, { children: /* @__PURE__ */ new Map() });
            node = node.get(seg).children;
          }
        }
        (function walk(node, depth) {
          for (const [seg, info2] of node) {
            let line = "  ".repeat(depth + 1) + seg;
            if (line.length > 100) line = line.slice(0, 100);
            lines.push(line);
            walk(info2.children, depth + 1);
          }
        })(tree, 0);
      }
      return lines.length ? lines.join("\n") + "\n" : "";
    }
    async function assembleArea2(areaKey, root) {
      root = root || process.cwd();
      if (!isEnabled(root)) {
        return { area: areaKey, disabled: true, fileCount: 0, tokenEstimate: 0, rederived: [], cached: [], slice: "" };
      }
      const absDir = path.resolve(root, areaKey);
      const index = readIndex(root);
      const prev = index.areas && index.areas[areaKey] || { files: {} };
      const fyiSentinel = path.join(mapDir(root), ".fyi-shown");
      const firstBuild = !fs2.existsSync(fyiSentinel);
      let files = [];
      try {
        files = enumerate(absDir).filter((f) => !f.includes("/"));
      } catch {
        files = [];
      }
      const perFile = [];
      const rederived = [];
      const cached = [];
      const newFiles = {};
      for (const f of files) {
        const abs = path.join(absDir, f);
        const rel = path.relative(root, abs).split(path.sep).join("/");
        try {
          const buf = fs2.readFileSync(abs);
          const hash = crypto.createHash("sha256").update(buf).digest("hex");
          const stored = prev.files[rel];
          let result;
          if (stored && stored.hash === hash) {
            result = { file: rel, tier: stored.tier, language: stored.language, floored: stored.floored, anchors: stored.anchors };
            cached.push(rel);
          } else {
            result = await extract2(abs, root);
            rederived.push(rel);
          }
          perFile.push({ rel, source: buf.toString("utf8"), result, hash });
          newFiles[rel] = { hash, tier: result.tier, language: result.language, floored: result.floored, anchors: result.anchors };
        } catch {
          perFile.push({ rel, source: "", result: { file: rel, tier: "floor", language: "unknown", floored: true, anchors: [] }, hash: "" });
          newFiles[rel] = { hash: "", tier: "floor", language: "unknown", floored: true, anchors: [] };
          rederived.push(rel);
        }
      }
      const ranked = rankDefinitions(perFile);
      const fileMeta = new Map(perFile.map((f) => [f.rel, { tier: f.result.tier, language: f.result.language }]));
      const budget = getBudget(root);
      const included = trimToBudget(ranked, (subset) => renderSlice(subset, fileMeta), budget);
      const slice = renderSlice(included, fileMeta);
      index.version = 1;
      index.areas = index.areas || {};
      index.areas[areaKey] = { headSha: headSha(root), files: newFiles };
      writeIndex(root, index);
      let fyi = null;
      if (firstBuild) {
        const anyGrammar = perFile.some((f) => !f.result.floored && f.result.anchors.length > 0 && f.result.tier !== "floor");
        fyi = anyGrammar ? "craft is building a structural map with its bundled parser - disable with `map.enabled: false`." : "craft maps in basic mode here (full parsing unavailable) - see the map reference for details.";
        fs2.writeFileSync(fyiSentinel, "shown\n");
      }
      return {
        area: areaKey,
        fileCount: files.length,
        budget,
        tokenEstimate: estimateTokens(slice),
        rederived,
        cached,
        firstBuild,
        fyi,
        slice
      };
    }
    module2.exports = { assembleArea: assembleArea2, renderSlice, getBudget };
  }
});

// src/cli.js
var lib = require_index();
var { extract } = require_extract();
var { assembleArea } = require_assemble_area();
function countNodes(node) {
  let n = 1;
  let errors = 0;
  if (node.type === "ERROR" || node.isMissing) errors++;
  for (let i2 = 0; i2 < node.namedChildCount; i2++) {
    const r = countNodes(node.namedChild(i2));
    n += r.n;
    errors += r.errors;
  }
  return { n, errors };
}
async function cmdParse(argv) {
  const file = argv[0];
  const languageId = argv[1] || lib.detectLanguage(file);
  if (!lib.GRAMMAR_WASM[languageId]) {
    return {
      tier: "floor",
      reason: languageId === "floor" ? "no-grammar-for-extension" : `no-grammar:${languageId}`,
      language: languageId,
      file
    };
  }
  const { tree } = await lib.parseFile(require("path").resolve(file), languageId);
  const counts = countNodes(tree.rootNode);
  return {
    ok: true,
    tier: "grammar",
    language: languageId,
    file,
    rootType: tree.rootNode.type,
    hasError: tree.rootNode.hasError,
    nodeCount: counts.n,
    errorCount: counts.errors
  };
}
function cmdDetect(argv) {
  return { file: argv[0], language: lib.detectLanguage(argv[0]) };
}
function cmdEnumerate(argv) {
  const dir = require("path").resolve(argv[0] || ".");
  return { dir, files: lib.enumerate(dir) };
}
async function cmdProbe() {
  try {
    await lib.initParser();
  } catch (e) {
    return { node: true, runtime: "failed", mode: "floor", grammars: {}, error: String(e && e.message || e) };
  }
  const grammars = {};
  for (const languageId of Object.keys(lib.GRAMMAR_WASM)) {
    try {
      await lib.loadLanguage(languageId);
      grammars[languageId] = true;
    } catch {
      grammars[languageId] = false;
    }
  }
  const loaded = Object.values(grammars).filter(Boolean).length;
  const total = Object.keys(grammars).length;
  const mode = loaded === 0 ? "floor" : loaded < total ? "partial" : "full";
  return { node: true, runtime: "loaded", mode, grammars };
}
async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  let result;
  switch (cmd) {
    case "parse":
      result = await cmdParse(rest);
      break;
    case "detect":
      result = cmdDetect(rest);
      break;
    case "enumerate":
      result = cmdEnumerate(rest);
      break;
    case "probe":
      result = await cmdProbe();
      break;
    case "extract":
      result = await extract(rest[0]);
      break;
    case "assemble":
      result = await assembleArea(rest[0]);
      break;
    default:
      process.stderr.write(`unknown command: ${cmd}
`);
      process.exit(2);
  }
  process.stdout.write(JSON.stringify(result) + "\n");
}
module.exports = { ...lib, extract, assembleArea };
if (require.main === module) {
  main().catch((e) => {
    process.stderr.write(`runner error: ${String(e && e.message || e)}
`);
    process.exit(1);
  });
}
