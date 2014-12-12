express = require("express")
Crawler = require("crawler")
router = express.Router()
db = require("../models")
RSS = require("rss")
dateFormat = require("dateformat")
groupUrl = "http://skunk.cc/groupMessages.php?id="
diaryUrl = "http://skunk.cc/diary.php?id="
c = new Crawler(
  maxConnections: 10
  callback: (error, result, $) ->
)

getSiteUrl = (typeNum, id) ->
  if typeNum is 1
    groupUrl + id
  else diaryUrl + id  if typeNum is 0

getFeedUrl = (typeNum, id) ->
  if typeNum is 1
    return "/group/" + id
  else
    return "/diary/" + id
  return

renderXml = (subscription, req, res) ->
  feed = new RSS(
    title: subscription.title
    description: subscription.title
    feed_url: req.headers.host + getFeedUrl(subscription.is_group, subscription.site_id)
    site_url: getSiteUrl(subscription.is_group, subscription.site_id)
    ttl: "60"
  )
  db.Entry.findAll(
    where:
      id: subscription.id

    order: "modified_on DESC"
  ).then (entries) ->

    entries.forEach (entry) ->
      modOn = new Date(entry.modified_on)
      feed.item
        title: (if subscription.is_group is 1 then entry.entry_title else dateFormat(modOn, "yyyy-mm-dd HH:MM:ss"))
        description: entry.text
        url: getSiteUrl(subscription.is_group, subscription.site_id) + "#" + dateFormat(modOn, "yyyy-mm-dd HH:MM:ss") # link to the item
        date: dateFormat(modOn, "yyyy-mm-dd HH:MM:ss") # any format that js Date can parse.

      return

    res.set "Content-Type", "text/xml"
    res.send feed.xml()
    return

  return

router.get "/:is_group(group|diary)/:id(\\d+)", (req, res) ->
  id = req.params.id
  db.Subscription.findOrCreate(
    where:
      site_id: id
      is_group: (if req.params.is_group is "group" then 1 else 0)

    defaults:
      retrieved_on: new Date()
  ).spread (subscription, created) ->
    refreshMeDate = new Date()
    refreshMeDate.setMinutes refreshMeDate.getMinutes() - 180
    if subscription.retrieved_on < refreshMeDate or created
      url = getSiteUrl(subscription.is_group, subscription.site_id)
      c.queue [
        uri: url
        jQuery: true
        callback: (error, result, $) ->
          feedTitle = $(".rightMenu > .bigHeader").text()
          retrievedEntryDate = undefined
          text = undefined
          entryTitle = undefined
          $(".mainContent .smallHeader").each (index, header) ->
            retrievedEntryDate = $(header).text().match(/[\d]{4}\W[\d]{2}\W[\d]{2}\s[\d]{2}\W[\d]{2}\W[\d]{2}/)[0]
            text = $(header).next().html()
            return false  if retrievedEntryDate < subscription.retrieved_on
            return true  if text.trim().length is 0
            if subscription.is_group is 1
              entryTitle = $(header).find("a").text() + " " + retrievedEntryDate
            else
              entryTitle = retrievedEntryDate
            db.Entry.findOrCreate
              where:
                id: subscription.id
                modified_on: new Date(retrievedEntryDate)

              defaults:
                text: text
                entry_title: entryTitle

            return

          subscription.retrieved_on = new Date()
          subscription.title = feedTitle
          unless feedTitle is "undefined"
            subscription.save().then ->
              renderXml subscription, req, res
              return

          else
            subscription.save(fields: ["retrieved_on"]).then ->
              renderXml subscription, req, res
              return

          return
      ]
    else
      renderXml subscription, req, res
    return

  return

router.all "/(:asd|)", (req, res) ->
  res.render "index",
    asd: req.params.asd

  return

module.exports = router
