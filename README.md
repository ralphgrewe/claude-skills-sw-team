# claude-skills-sw-team
Skills to make claude act like an agile SW development team

# Github APP for Claude SW Team
I'm using the Claude Github MCP and fine grained acces tokens so that Claude can read/write issues and commit/push to the repository. While it perfectly works using tokens from the developer account, it's a bit confusing because all work on the issues is done by the same user. As a private user is only allowed to have a single account, the proposed solution is to create a app for claude. Therefore, in your github account go to: Github (your user icon on the top right edge of the screen) -> Settings > Developer Settings and create a new App with the following settings:

* GitHub App Name, Description and Homepage URL you can freely chose
* Webhook you can deactivate
* Repository permissions (Assuming we can give them more fine-granular on APP installation):
** Content: Read & Write
** Issues: Read & Write
** Pull Requests: Read & Write
