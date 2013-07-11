// transition helpers


function setup_help_transitions() {
    $(".paramhelp").on("click", toggle_description);
}

function toggle_description(event) {
    var desc = $(this).children(".paramdesc");
    if( desc.length > 0 ) {
        if( desc.is(":visible") ) {
            desc.slideUp();
        } else {
            desc.slideDown();
        }
    } else {
        console.log("jQuery selector empty");
    }
}


// Value guards for each of the app's parameters.

// guards are added to input fields as JSON objects injected into 
// the app.tt template.

// guards = {
//      file: '.cub',
//      text: 'int/double/string'
//      mandatory: t or f
//      range: { gt , gte , lt , lte }
//      inclusions: [ p1, p2, p3 ]
//      exclusions: [ p1, p2, p3 ]
// }

function add_guards(param, guards) {





// Guard handlers are activated when an input field loses
// focus, and on form submission.

function guard_input_file(event) {
    
