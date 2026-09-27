const allowedContextFields = [
    'requestId',
    'method',
    'route',
    'statusCode',
    'durationMs',
    'errorCode',
];

function createLogEntry(
    level,
    event,
    context = {},
    now = new Date(),
) {
    const entry = {
        timestamp: now.toISOString(),
        level,
        event,
    };

    for (const field of allowedContextFields) {
        if (context[field] !== undefined) {
            entry[field] = context[field];
        }
    }

    return entry;
}

function writeLog(
    level,
    event,
    context = {},
    output = console,
    now = new Date(),
) {
    const entry = createLogEntry(
        level,
        event,
        context,
        now,
    );
    const line = JSON.stringify(entry);

    if (level === 'error') {
        output.error(line);
    } else if (level === 'warn') {
        output.warn(line);
    } else {
        output.log(line);
    }

    return entry;
}

module.exports = {
    createLogEntry,
    writeLog,
};
