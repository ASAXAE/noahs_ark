function createFakeVerificationMailer() {
    const sentMessages = [];

    return {
        sentMessages,
         async sendVerificationEmail({ to, token }) {
            sentMessages.push({ to, token });
         },
    };
}

module.exports = {
   createFakeVerificationMailer,
}