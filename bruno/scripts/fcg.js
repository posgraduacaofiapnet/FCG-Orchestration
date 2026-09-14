const gateway = () => "http://localhost:8000";

function bodyOf(res) {
  if (!res) return {};
  if (res.data && typeof res.data === "object") return res.data;
  if (res.body && typeof res.body === "object") return res.body;
  return {};
}

async function login(bru, email, password) {
  const res = await bru.sendRequest({
    method: "POST",
    url: `${gateway()}/api/auth/login`,
    headers: { "Content-Type": "application/json" },
    data: { email, password }
  });
  const body = bodyOf(res);
  return {
    token: body.token || body.Token || "",
    userId: String(body.userId || body.UserId || "")
  };
}

async function loginAdmin(bru) {
  return login(
    bru,
    bru.getEnvVar("adminEmail") || "admin@fcg.com",
    bru.getEnvVar("adminPassword") || "AdminSenha@123"
  );
}

async function loginUser(bru) {
  return login(
    bru,
    bru.getEnvVar("userEmail") || "user@fcg.com",
    bru.getEnvVar("userPassword") || "Senha@123"
  );
}

async function findGameId(bru, titlePart) {
  const res = await bru.sendRequest({
    method: "GET",
    url: `${gateway()}/api/games?page=1&pageSize=100`
  });
  const body = bodyOf(res);
  const items = body.items || body.Items || [];
  const game = items.find((item) => String(item.title || item.Title || "").includes(titlePart));
  return game ? String(game.id || game.Id) : "";
}

module.exports = { gateway, loginAdmin, loginUser, findGameId };
