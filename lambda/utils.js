// Generates a short random ID
exports.generateId = () => {
    return Math.random().toString(36).substr(2, 9);
};