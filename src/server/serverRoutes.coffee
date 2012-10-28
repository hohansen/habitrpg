scoring = require('../app/scoring')
_ = require('underscore')

module.exports = (expressApp, root, derby) ->

  # ---------- Static Pages ------------
  staticPages = derby.createStatic root
    
  expressApp.get '/privacy', (req, res) ->
    staticPages.render 'privacy', res
  
  expressApp.get '/terms', (req, res) ->
    staticPages.render 'terms', res

  # ---------- REST API ------------  

  # Deprecated API (will remove soon)
  deprecatedMessage = 'This REST resource is no longer supported, use /users/:uid/tasks/:taskId/:direction instead.'
  expressApp.get '/:uid/up/:score?', (req, res) ->
    res.send(200, deprecatedMessage)
  expressApp.get '/:uid/down/:score?', (req, res) ->
    res.send(200, deprecatedMessage)

  # New API
  expressApp.post '/users/:uid/tasks/:taskId/:direction', (req, res) ->
    {uid, taskId, direction} = req.params
    {title, service, icon} = req.body
    console.log {params:req.params, body:req.body}
    return res.send(500, ":direction must be 'up' or 'down'") unless direction in ['up','down']
    model = req.getModel()
    model.session.userId = uid
    model.fetch "users.#{uid}", (err, user) ->
      return res.send(500, err) if err
      userObj = user.get()
      #FIXME The server keeps crashing. I think it's because some users are entering non-guids as their userId, test that here
      unless userObj && userObj.stats && userObj.stats.money && !_.isEmpty(userObj.tasks)
        console.log {taskId:taskId, direction:direction, user:userObj, error: 'non-user attempted to score'}
        return res.send(500, "User #{uid} not found") 
       
      model.ref('_user', user)
      
      # Create task if doesn't exist
      # TODO add service & icon to task
      unless model.get("_user.tasks.#{taskId}")
        model.refList "_habitList", "_user.tasks", "_user.habitIds"
        model.at('_habitList').push {
          id: taskId
          type: 'habit'
          text: (title || taskId) + ' *'
          value: 0
          up: true
          down: true
          notes: "This task was created by a third-party service. Feel free to edit, it won't harm the connection to that service. Additionally, multiple services may piggy-back off this task."
        }

      scoring.setModel(model)
      delta = scoring.score(taskId, direction)
      result = model.get ('_user.stats')
      result.delta = delta
      res.send(result)

  # ---------- Stripe ------------

  expressApp.post '/', (req) ->
    require('../app/reroll').stripeResponse(req)

  # ---------- Errors ------------

  expressApp.all '*', (req) ->
    throw "404: #{req.url}"