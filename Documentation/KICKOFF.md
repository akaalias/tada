I was talking with a friend of mine about a task-management / todo app he's been building and I had this idea that I would love to test out. 



Let me give you a bit of context of what I'm thinking:



I currently use (and pay) for todoist. It's a classic todo manager with projects, tasks, sub-tasks etc. Everything is done by me, the app is a well-designed CRUD UI / UX for human-based task management. 



That's great. 



Now, the first layer (what my friend is working on) is to use AI (llms) to help with the existing UI/UX and busy-work of task management. 



The main idea of his is that when I add a new task by typing (or speaking) "I need to revitalize my balcony because I don't spend much time there and summer is coming but I don't even know where to start" which is then saved and then sent to AI to:





write an actual good task title



write an actual good task description



think about a plan and then automatically create sub-tasks for this task



That in itself would be great to have even in Todoist!



Now, here is the NEW idea that I would like to build on top of EVEN that:



I would like to build an app that does all of that AND NOW allows me to EXECUTE on those sub tasks WITHIN the app directly. 



What I mean is: Assume I have a bunch of tasks, each with sub tasks etc. (created by me and/or the AI)



That would include the balcony one:



**Top-level task: Turn the balcony into a space I'll actually use this summer**

Description: Transform an underused balcony into somewhere genuinely inviting in time for summer — starting with clarity on how you want to use it, then building outward from there.

Initial plan:





Decide how you want to use the balcony. Pick 1–2 concrete uses (morning coffee, evening dinners, reading nook, plant corner). This is the anchor — every later decision flows from it, and skipping it is the main reason balcony refreshes stall.



Audit the space. Measure dimensions, observe the sun/shade pattern across a day, note what's dirty, broken, or worth keeping. You now know what you're working with.



Clear and deep clean. Remove clutter, scrub surfaces, fix the obvious stuff. Get to a blank-canvas state before buying anything new.



Set a budget and shop. Furniture, greenery, shade/lighting, textiles — sized to your chosen uses and what the audit revealed. One focused shopping pass beats five scattered ones.



Set it up and live-test it for a week. Install everything, then actually spend time out there daily. Note what's uncomfortable, missing, or unused, and adjust. The space isn't "done" until it passes the use-it test.


## Action Required Dashboard


At the very top of the main navigation there is a "Action Required" section. When I click on that, another AI now goes thorugh each of my top-level tasks and takes the most actionable / reasonable sub-task from each. 



Now, for each of those sub-tasks (one per top-level task so it doesn't get too crazy) I want the AI to AUTOMATICALLY generate or choose a custom UI to complete that one sub-task. 



This means, for our balcony task: the first sub-task is "Decide how you want to use the balcony. Pick 1–2 concrete uses" 



So what I see as the first Action Item is:

--- ACTION REQUIRED ITEM ---

	Task: Turn the balcony into a space I'll actually use this summer
	
	Sub-Task: Decide how you want to use the balcony.
	
	Action Required: An ACTUAL form that asks me to select one or many of the following options:
	
	--- form ---
	Please tell me how you want to use the balcony:
	
	- morning coffee
	- day-time home office
	- evening dinners
	- reading nook
	- plant corner
	
	And a button to submit my answer. 
	
	--- /form ---

--- /ACTION REQUIRED ITEM ---


I make my pick of one or more options and hit the Submit button.

That is of course locally saved and this marks the task as “complete”. But instead of ticking off the todo checkbox to mark it as complete, the actual submit button is the “complete” button!!!

By ACTUALLY being able to take the requested ACTION  (instead of going somewhere else to do it and then come back to the app to check off the checkbox) I provide the planner AI the context needed to either keep the existing plan and next sub-task ("Audit the space.") or even revise the sub-tasks based on the new information. 

So, let's say, the planner AI looks at this input and the current plan and decides that "Audit the space." Is still the next best step to take. 

So, in case of the “Decide how you want to use the balcony” task, the planner AI came up with a required action that uses a multi-select UI/UX. Makes sense. 

Now, for "Audit the space" it may come up with something completely different. 

Here the executive AI may look at “Audit the space” and come up with a simple two-input form: 

(Same layout like above, just a different form)

Balcony width (in m): [        ]
Balcony depth (in m): [        ]
[Submit]

And this time, I am prompted to provide those two values via two  inputs + submit button. And again, submitting this form results in the sub-task to be completed AND it triggers a re-evaluation of the current plan based on the new information. 

And I want the executive AI, the one who comes up with required actions and easiest-to-accomplish UI for the end-user (me) to make it super simple to get input from the user to keep moving forward.

And this can be super creative, too! Not just always form elements (but that’s a good start)

Depending on what our planner and executive AI needs, it could also have been a “Here’s a small area you can draw in. Please draw the shape of your balcony and add an arrow to indicate where north is”) or something like that. 

The point is that the executive UI/UX (that which lets the human provide the required action to the app) is created completely ad-hoc and on the fly based on the current situation. Of course, ideally, it is always actionable by the user and ideally doesn’t take long. 

But the main point being: 

1. My ideal task app has the solid foundation of a CRUD-type UI/UX like Todoist
2. Whenever I add a new task, a planner / coach AI helps me by turning it into an initial plan, clean up title etc.
3. Based on the next most critical sub-task from that plan, the executive AI thinks about and comes up with an on-demand UI/UX that lets me accomplish that sub-task directly in the app (in the action required / action items / required actions) section of the app
4. And based on the input I give via this on-demand UI and the information I provided, the planner potentially revises the plan based (or sticks with what was there before) and the executive AI already prepares and provides the UI for the next task. 


## My challenge for you, Claude:

I want to test this idea the use of these two types of AI agents that results in the automatic planning and creation of those custom-made, ad-hoc “Action items” that I complete in the app directly. 

For this I’ve given you enough information to bootstrap a basic todo app that:

1. Lets me CRUD tasks and sub-tasks by hand
2. Adds the planner AI loop that takes a newly created (top-level) task and turns it into a well-planned mini-project by creating the sub-tasks
3. Adds the executive AI loop that provides me with those on-demand UI/UX action items in that special section of the app
4. Lets me complete tasks based on those on-demand actions
5. Lets the planner AI use that new input to potentially revise the plan

Technically, I want to test this using a standard native macOS app. 

And for this I want you to write a PRD and a technical requirements document that I can then give to my coding agents to implement. 

Can you do this for me?
