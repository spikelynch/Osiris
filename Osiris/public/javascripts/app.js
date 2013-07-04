// transition helpers


function setup_help_transitions() {
    $(".paramhelp").on("click", toggle_description);
}


function setup_guards(guards) {
    
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
