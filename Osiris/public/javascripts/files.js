/* Ajax callbacks for file browsing */

/* filebrowser_init(bid, ctrlid, filter, selected)

   bid is the id of the containing element (b = 'browser').
   
   ctrlid is the id of the element to which to bind an onClick event 
   opening this browser.
   
   filter is a regexp which matches the allowed filetypes

   selected is a function to be called when the user selects a file. 

   Three arguments are passed to this- jobid, filename and output.
   output is a boolean indicating whether the file selected was an
   output of the job - this is used to build workflows.

   Note that bid should not contain underscores (which sucks)

*/

function filebrowser_init(bid, ctrlid, filter, selected) {
    var elt = $('#' + bid);
    elt.empty();
    elt.addClass('filebrowser');
    elt.data("selected", selected);
    elt.data("status", "closed");
    $('#' + ctrlid).click(function (event) {
        filebrowser(event, bid, filter);
    });
}

/* filebrowser - open or close a filebrowser's job list */

function filebrowser(event, bid, filter) {
    var elt = $(this);
    var browser = $('#' + bid);
    console.log("filebrowser: " + bid + " " + filter);
    if( browser.data("status") == "closed" ) {
        $.getJSON(
            '/jobs/' + filter,
            function(jobs) {
                for ( var jid in jobs ) {
                    console.log("Here is a job " + jid);
                    var id = bid + '_' + jid;
                    browser.append('<div class="filebrowser_job" id="' + id + '">Job ' + jobs[jid].label + '</div>');
                    $('#' + id).data('job', jobs[jid]);
                    $('#' + id).click(filebrowser_job);
                }
                browser.data("status", "open");
            }
        );
    } else {
        browser.empty();
        browser.data("status", "closed");
    }
}

/* filebrowser_job: opens or closes a job's file list 
   This is a new version which doesn't do an ajax call but gets it
   from the data object bound when the job list is build.
*/

function filebrowser_job(event) {
    event.stopPropagation();
    var fb = $(this).parent();
    var bid = $(this).parent().attr('id');
    var job = $(this).data("job");
    var jid = job.id;

    console.log("bid = " + bid + "; jid = " + jid);
    
    var id = bid + '_' + jid;
    var fid = id + "_files";

    console.log("Open " + bid + ", " + jid + ", " + id);

    if( $(this).data("open") ) {
        $("#" + fid).remove();
        $(this).data("open", false);
    } else {
        $(this).after('<div class="files" id="' + fid + '"></div>');
        filebrowser_files(id, job);
        $(this).data("open", true);
    }
    return false;
}

/* filebrowser_files - write each set of files (Input / Output) */

function filebrowser_files(id, job) {
    var elt = $("#" + id + "_files");
    console.log("adding to #" + id + "_files");
    if( job.inputs ) {
        filebrowser_filelist(elt, id, 'Inputs', job.inputs);
    }
    if( job.outputs ) {
        filebrowser_filelist(elt, id, 'Outputs', job.outputs);
    }
    elt.children('.file').click(filebrowser_select);
}


/* filebrowser_filelist - write a list of files */

/* A bit of a hack here - output files get an extra class, 'output',
   because that's simpler than storing a jquery data against each file - 
   the '.' in filenames stuffs up jQuery selectors */

function filebrowser_filelist(elt, id, header, files) {
    elt.append('<div class="fhead">' + header + '</div>');
    console.log("files = " + $(files).dump());
    for ( var i = 0; i < files.length; i++ ) {
        var file = files[i];
        var fileid = id + '_' + file;
        var cl = "file";
        if( header == 'Outputs' ) {
            cl = cl + ' output';
        }
        elt.append('<div class="' + cl + '" id="' + fileid + '">'  + file + '</div>');
    }
}
    

/* filebrowser_select - called when a filename is clicked */

function filebrowser_select(event) {
    event.stopPropagation();
    var fileid = $(this).attr('id');
    var targetid = event.target.id;
    var browser = $(this).parents('.filebrowser');

    browser.find('.file').removeClass('selected');
    $(this).addClass('selected');
    var callback = browser.data('selected');
    if( callback ) {
        var output = false;

        if( $(this).hasClass('output') ) {
            output = true;
        }

        var fields = fileid.split('_');
        callback(fields[1], fields[2], output);
    }
}




