C#:

_hub.Clients.Group($"user:{ownerId}").SendAsync("QuestionnaireStatusChanged", evt);
_hub.Clients.Group($"user:{ownerId}").SendAsync("QuestionnaireChanged", evt);

JS

 // Event 1: status updates sent to my room
  connection.on("QuestionnaireStatusChanged", (evt) => {
    log(`[STATUS] ${evt.questionnaireId}: ${evt.previousStatus} → ${evt.status}`);
  });

  // Event 2: any change sent to my room
  connection.on("QuestionnaireChanged", (evt) => {
    log(`[CHANGE] ${evt.questionnaireId}: ${evt.changeType} at ${evt.path}`);
  });

  async function joinMyRoom() {
    await connection.invoke("JoinRoom", myUserId);
    log(`Joined room ${myUserId}`);
  }