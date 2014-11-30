
user = id: 1, name: "yannick"
oldUser = role: "lol", name: "bob"
for key, value of oldUser
  unless key of user
    user[key] = value
console.log user, oldUser
