function createFakePasswordResetMailer() {
    const sentMessages = [];

    return {
        sentMessages,

        async sendPasswordResetEmail({ to, token }) {
            sentMessages.push({
                to,
                token,
            });
        },
    };
}

module.exports = {
    createFakePasswordResetMailer,
};