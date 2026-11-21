(function (host, parse, stringify) {
    'use strict';
    delete globalThis.__expressiveHost;
    const events = Object.create(null);
    const panels = [];
    const buttons = [];
    let itemCallbacks = [];
    let promisedInput;
    const requestInput = options => new Promise(resolve => { promisedInput = resolve; call('input', options); });
    function describe(item) {
        if (typeof item === 'string') return { type: 'button', text: item };
        if (!item || typeof item !== 'object') return {};
        const copy = { ...item };
        if (typeof item.onClick === 'function') {
            copy.callback = itemCallbacks.push(item.onClick) - 1;
            delete copy.onClick;
        }
        if (typeof item.onChange === 'function') {
            copy.change = itemCallbacks.push(item.onChange) - 1;
            delete copy.onChange;
        }
        if (Array.isArray(item.children)) copy.children = item.children.map(describe);
        return copy;
    }
    const call = (name, ...args) => parse(host(name, stringify(args)));
    const no = () => undefined;
    const overlay = Object.fromEntries(['clear', 'circle', 'rect', 'line', 'text'].map(
        type => [type, (...args) => call('draw', type, ...args)]
    ));
    overlay.set = items => call('draw', 'set', items);
    const api = {
        on: (name, callback) => {
            if (typeof callback === 'function') (events[name] ||= []).push(callback);
        },
        off: name => delete events[name],
        addPanel: panel => { if (panels.length < 24) panels.push(panel); },
        addButton: button => { if (buttons.length < 24) buttons.push(button); },
        commit: text => call('commit', text),
        deleteBefore: count => call('deleteBefore', count),
        deleteAfter: count => call('deleteAfter', count),
        moveCursor: count => call('move', count),
        textBefore: count => call('textBefore', count),
        textAfter: count => call('textAfter', count),
        selectedText: () => call('selectedText'),
        clipboard: () => call('clipboard'),
        status: message => call('status', message),
        toast: message => call('status', message),
        refresh: () => call('refresh'),
        closePanel: () => call('closePanel'),
        haptic: () => call('haptic'),
        speak: text => call('speak', text),
        stopSpeaking: () => call('stopSpeaking'),
        keyboardSize: () => call('size'),
        device: () => call('device'),
        input: requestInput,
        captureTouches: enabled => call('capture', enabled),
        pressKey: key => call('pressKey', key),
        storage: {
            get: (key, fallback) => call('get', key) ?? fallback,
            set: (key, value) => call('set', key, value),
            remove: key => call('set', key, null)
        },
        config: key => call('config', key),
        setConfigs: values => call('setConfigs', values),
        supports: feature => ['overlay', 'storage', 'input'].includes(feature),
        overlay,
        particles: { count: () => 0, emit: no, remove: no, set: no },
        keyboardEffect: no, postEffect: no
    };
    Object.defineProperty(globalThis, 'kb', { value: Object.freeze(api) });
    globalThis.console = { log: (...items) => call('log', items.join(' ')) };
    Object.defineProperty(globalThis, '__expressiveDispatch', { value: (name, arg) => {
        switch (name) {
        case '$catalog':
            return { panels: panels.map(({id, title, icon}) => ({id, title, icon})),
                buttons: buttons.map(({title, icon}) => ({title, icon})) };
        case '$render': {
            const panel = panels[arg];
            if (!panel) return [];
            itemCallbacks = [];
            const source = panel.render ?? panel.items ?? [];
            const rows = typeof source === 'function' ? source() : source;
            return Array.isArray(rows) ? rows.map(describe) : [];
        }
        case '$panelOpen':
            panels[arg]?.onOpen?.();
            return null;
        case '$panelClose':
            panels[arg]?.onClose?.();
            return null;
        case '$panelPick': return itemCallbacks[arg[0]]?.(arg[1]);
        case '$input': { const callback = promisedInput; promisedInput = undefined; return callback?.(arg); }
        case '$button': return buttons[arg]?.onClick?.();
        default: {
            let result = null;
            for (const handler of events[name] || []) {
                const value = handler(arg);
                if (value !== undefined) result = value;
            }
            return result;
        }
        }
    }});
    Object.defineProperty(globalThis, '__expressiveJSON', { value: stringify });
})(globalThis.__expressiveHost, JSON.parse, JSON.stringify);
