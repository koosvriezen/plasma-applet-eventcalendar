import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "../Shared.js" as Shared
import "../lib/Async.js" as Async
import "../lib/Requests.js" as Requests

// import "./GoogleCalendarTests.js" as GoogleCalendarTests

GoogleApiManager {
	id: googleTasksManager

	calendarManagerId: "googletasks"

	onFetchAllCalendars: {
		fetchGoogleAccountData()
	}

	function fetchGoogleAccountData() {
		if (accessToken) {
			fetchGoogleAccountTasks(['@default'])
		}
	}

	//-------------------------
	// CalendarManager
	function getCalendar(calendarId) {
		return {
			id: calendarId,
			backgroundColor: theme.highlightColor
		}
	}


	//-------------------------
	// Tasks
	function fetchGoogleAccountTasks(tasklistIdList) {
		googleCalendarManager.asyncRequests += 1
		var func = fetchGoogleAccountTasks_run.bind(this, tasklistIdList, function(errObj, data) {
			if (errObj) {
				fetchGoogleAccountTasks_err(errObj.err, errObj.data, errObj.xhr)
			} else {
				fetchGoogleAccountTasks_done(data)
			}
		})
		checkAccessToken(func)
	}
	function fetchGoogleAccountTasks_run(tasklistIdList, callback) {
		logger.debug('fetchGoogleAccountTasks_run', tasklistIdList)

		var tasks = []
		for (var i = 0; i < tasklistIdList.length; i++) {
			var tasklistId = tasklistIdList[i]
			var task = fetchGoogleTasks.bind(this, tasklistId)
			tasks.push(task)
		}

		Async.parallel(tasks, callback)
	}
	function fetchGoogleAccountTasks_err(err, data, xhr) {
		logger.debug('fetchGoogleAccountTasks_err', err, data, xhr)
		googleCalendarManager.asyncRequestsDone += 1
		return handleError(err, data, xhr)
	}
	function fetchGoogleAccountTasks_done(results) {
		for (var i = 0; i < results.length; i++) {
			var tasklistId = results[i].tasklistId
			var tasklistData = results[i].data
			var eventList = parseTasklistAsEvents(tasklistData)
			setCalendarData(tasklistId, eventList)
		}
		googleCalendarManager.asyncRequestsDone += 1
	}

	function parseTasklistAsEvents(tasklistData) {
		var eventList = []
		for (var i = 0; i < tasklistData.items.length; i++) {
			var taskData = tasklistData.items[i]
			var eventData = parseTaskAsEventData(taskData)
			logger.logJSON('tasklistData', i, eventData)
			eventList.push(eventData)
		}
		return {
			items: eventList,
		}
	}

	function parseTaskAsEventData(taskData) {
		// Don't bother creating a new object.
		var eventData = taskData

		var editTasksUrl = 'https://tasks.google.com/embed/?origin=' + encodeURIComponent('https://calendar.google.com') + '&fullWidth=1'
		eventData.htmlLink = editTasksUrl

		eventData.isCompleted = taskData.status == "completed"

		if (taskData.due) {
			var startDateTime = new Date(taskData.due)
		} else {
			var today = new Date()
			var startDateTime = new Date(today.getFullYear(), today.getMonth(), today.getDate())
		}
		var endDateTime = new Date(startDateTime)
		endDateTime.setDate(endDateTime.getDate() + 1)
		eventData.start = {
			date: Shared.dateString(startDateTime),
		}
		eventData.end = {
			date: Shared.dateString(endDateTime),
		}

		logger.debugJSON('task', startDateTime, endDateTime)

		return eventData
	}

	function fetchGoogleTasks(tasklistId, callback) {
		logger.debug('fetchGoogleTasks', tasklistId)
		fetchGCalTasks({
			tasklistId: tasklistId,
			// start: googleCalendarManager.dateMin.toISOString(),
			// end: googleCalendarManager.dateMax.toISOString(),
			access_token: accessToken,
		}, function(err, data, xhr) {
			if (err) {
				logger.logJSON('onErrorFetchingTasks: ', err)
				var errObj = {
					err: err,
					data: data,
					xhr: xhr,
				}
				return callback(errObj, null)
			}

			return callback(null, {
				tasklistId: tasklistId,
				data: data,
			})
		})
	}

	function fetchGCalTasks(args, callback) {
		logger.debug('fetchGCalTasks', args.tasklistId)

		// return GoogleCalendarTests.testInvalidCredentials(callback)
		// return GoogleCalendarTests.testDailyLimitExceeded(callback)
		// return GoogleCalendarTests.testBackendError(callback)

		var onResponse = fetchGCalTasksPageResponse.bind(this, args, callback, null)
		fetchGCalTasksPage(args, onResponse)
	}

	function fetchGCalTasksPageResponse(args, finishedCallback, allData, err, data, xhr) {
		logger.debug('fetchGCalTasksPageResponse', args, finishedCallback, allData, err, data, xhr)
		if (err) {
			return finishedCallback(err, data, xhr)
		}
		if (allData) {
			data.items = allData.items.concat(data.items)
			delete allData.items
			delete allData
		}
		allData = data
		
		if (allData.nextPageToken) {
			logger.debug('fetchGCalTasksPageResponse.nextPageToken', allData.nextPageToken)
			logger.debug('fetchGCalTasksPageResponse.nextPageToken', 'allData.items.length', allData.items.length)
			args.pageToken = allData.nextPageToken
			var onResponse = fetchGCalTasksPageResponse.bind(this, args, finishedCallback, allData)
			fetchGCalTasksPage(args, onResponse)
		} else {
			logger.debug('fetchGCalTasksPageResponse.finished', 'allData.items.length', allData.items.length)
			finishedCallback(err, allData, xhr)
		}
	}

	function fetchGCalTasksPage(args, pageCallback) {
		logger.debug('fetchGCalTasksPage', args.tasklistId)
		var url = 'https://www.googleapis.com/tasks/v1'
		url += '/lists/'
		url += encodeURIComponent(args.tasklistId)
		url += '/tasks'
		url += '?showCompleted=true'
		url += '&showHidden=true'
		// url += '&dueMin=' + encodeURIComponent(args.start)
		// url += '&dueMax=' + encodeURIComponent(args.end)
		if (args.pageToken) {
			url += '&pageToken=' + encodeURIComponent(args.pageToken)
		}
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.access_token,
			}
		}, function(err, data, xhr) {
			logger.debug('fetchGCalTasksPage.response', args.tasklistId, err, data, xhr.status)
			if (!err && data && data.error) {
				return pageCallback(data, null, xhr)
			}
			// logger.debugJSON('fetchGCalTasksPage.response', args.tasklistId, data)
			pageCallback(err, data, xhr)
		})
	}
}
