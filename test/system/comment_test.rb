require 'test_helper'
require "application_system_test_case"
# https://guides.rubyonrails.org/testing.html#implementing-a-system-test

class CommentTest < ApplicationSystemTestCase
  Capybara.default_max_wait_time = 60

  def setup
    visit '/'

    find(".nav-link.loginToggle").click()
    fill_in("username-login", with: "jeff")
    fill_in("password-signup", with: "secretive")

    find(".login-modal-form #login-button").click()
  end

  def get_path(page_type, path)
    # wiki pages' comments, unlike questions' and notes', are viewable from /wiki/wiki-page-path/comments
    page_type == :wiki ? path + '/comments' : path
  end

  # page_types are wiki, research note, question:
  page_types.each do |page_type, node_name|
    page_type_string = page_type.to_s
    comment_text = 'woot woot'
    comment_response_text = 'wooly woot'

    test "#{page_type_string}: addComment(comment_text)" do
      visit get_path(page_type, nodes(node_name).path)
      page.evaluate_script("addComment('#{comment_text}')")
      assert_selector('#comments-list .comment-body p', text: comment_text)
    end

    test "#{page_type_string}: addComment(comment_text, submit_url)" do
      visit get_path(page_type, nodes(node_name).path)
      page.evaluate_script("addComment('#{comment_text}', '/comment/create/#{nodes(node_name).nid.to_s}')")
      assert_selector('#comments-list .comment-body p', text: comment_text)
    end

    test "#{page_type_string}: reply to existing comment" do
      visit get_path(page_type, nodes(node_name).path)
      # find comment ID of the first comment on page
      parent_id = "#" + page.find('#comments-list').first('.comment')[:id]
      parent_id_num = /c(\d+)/.match(parent_id)[1] # eg. comment ID format is id="c9834"
      # addComment(comment text, submitURL, comment's parent ID)
      page.evaluate_script("addComment(\"no you can't\", '/comment/create/#{nodes(:comment_note).nid}', #{parent_id_num})")
      # check for comment text
      assert_selector("#{parent_id} .comment .comment-body p", text: 'no you can\'t')
    end

    test "#{page_type_string}: comment, then reply to FRESH comment" do
      visit nodes(:comment_question).path
      # post new comment
      comment_text = 'woot woot'
      page.evaluate_script("addComment('#{comment_text}', '/comment/create/#{nodes(:comment_question).nid}')")
      # we need the ID of parent div that contains <p>comment_text</p>:
      parent_id = page.find('p', text: comment_text).find(:xpath, '..')[:id]
      # regex to strip the ID number out of string. ID format is comment-body-4231
      parent_id_num = /comment-body-(\d+)/.match(parent_id)[1]
      # reply to comment
      comment_response_text = 'wooly woot!'
      # addComment(comment text, submitURL, comment's parent ID)
      page.evaluate_script("addComment('#{comment_response_text}', '/comment/create/#{nodes(:comment_question).nid}', #{parent_id_num})")
      # assert that <div id="c1show"> has child div[div[p[text="wooly woot!"]]]
      assert_selector("#{'#c' + parent_id_num + 'show'} div div div p", text: comment_response_text)
    end

    test "#{page_type_string}: manual comment and reply to comment" do
      visit get_path(page_type, nodes(node_name).path)
      fill_in("body", with: comment_text)
      # preview comment
      find("#post_comment").click
      find("p", text: comment_text)
      # publish comment
      click_on "Publish"
      find(".noty_body", text: "Comment Added!")
      find("p", text: comment_text)
      # replying to the comment
      first("p", text: "Reply to this comment...").click()
      fill_in("body", with: comment_response_text)
      # preview reply
      first("#post_comment").click
      find("p", text: comment_response_text)
    end

    test "post #{page_type_string}, then comment on FRESH #{page_type_string}" do
      title_text, body_text = String.new, String.new
      case page_type_string
        when 'note'
          visit '/post'
          title_text = 'Ahh, a nice fresh note'
          body_text = "Can\'t wait to write in it!"
          fill_in('title-input', with: title_text)
          find('.wk-wysiwyg').set(body_text)
          find('.ple-publish').click()
        when 'question'
          visit '/questions/new?&tags=question%3Ageneral'
          title_text = "Let's talk condiments"
          body_text = 'Ketchup or mayo?'
          find("input[aria-label='Enter question']", match: :first)
            .click()
            .fill_in with: title_text
          find('.wk-wysiwyg').set(body_text)
          find('.ple-publish').click()
        when 'wiki'
          visit '/wiki/new'
          title_text = 'pokemon'
          body_text = 'Gotta catch em all!'
          fill_in('title', with: title_text)
          fill_in('text-input', with: body_text)
          find('#publish').click()
          visit "/wiki/#{title_text}/comments"
      end
      assert_selector('h1', text: title_text)
      fill_in("body", with: comment_text)
      # preview comment
      find("#post_comment").click
      find("p", text: comment_text)
      # publish comment
      click_on "Publish"
      find(".noty_body", text: "Comment Added!")
      find("p", text: comment_text)
    end

    test "#{page_type_string}: comment preview button works" do
      visit get_path(page_type, nodes(node_name).path)
      find("p", text: "Reply to this comment...").click()
      reply_preview_button = page.all('#post_comment')[0]
      comment_preview_button = page.all('#post_comment')[1]
      # Toggle preview
      reply_preview_button.click()
      # Make sure that buttons are not binded with each other
      assert_equal( reply_preview_button.text, "Hide Preview" )
      assert_equal( comment_preview_button.text, "Preview" )
    end

    test "#{page_type_string}: IMMEDIATE image SELECT upload into MAIN comment form" do
      visit get_path(page_type, nodes(node_name).path)
      main_comment_form =  page.find('h4', text: /Post comment|Post Comment/).find(:xpath, '..') # title text on wikis is 'Post comment'
      Capybara.ignore_hidden_elements = false
      fileinput_element = main_comment_form.find('input#fileinput-button-main')
      # Upload the image
      fileinput_element.set("#{Rails.root.to_s}/public/images/pl.png")
      Capybara.ignore_hidden_elements = true
      # Wait for image upload to finish
      wait_for_ajax
      # Toggle preview
      main_comment_form.find('a', text: 'Preview').click
      # Make sure that image has been uploaded
      page.assert_selector('#preview img', count: 1)
    end

    # navigate to page, immediately upload into EDIT form by SELECTing image
    test "#{page_type_string}: IMMEDIATE image SELECT upload into EDIT comment form" do
      nodes(node_name).add_comment({
        uid: 2,
        body: comment_text
      })
      visit get_path(page_type, nodes(node_name).path)
      # open up the edit comment form
      page.find("#edit-comment-btn").click
      edit_comment_form = page.find('h4', text: 'Edit comment').find(:xpath, '..')
      # we need the comment ID:
      edit_comment_form_id = edit_comment_form[:id]
      # regex to strip the ID number out of string. ID format is #c1234edit
      comment_id_num = /c(\d+)edit/.match(edit_comment_form_id)[1]
      edit_preview_id = '#c' + comment_id_num + 'preview'
      # the <inputs> that take image uploads are hidden, so reveal them:
      Capybara.ignore_hidden_elements = false
      file_input_element = edit_comment_form.all('input')[1]
      file_input_element.set("#{Rails.root.to_s}/public/images/pl.png")
      wait_for_ajax
      Capybara.ignore_hidden_elements = true
      # open edit comment preview
      edit_comment_form.find('a', text: 'Preview').click
      # there should be 1 preview image in the edit comment
      assert_selector("#{edit_preview_id} img", count: 1)
    end

    test "#{page_type_string}: IMMEDIATE image SELECT upload into REPLY comment form" do
      nodes(node_name).add_comment({
        uid: 5,
        body: comment_text
      })
      nodes(node_name).add_comment({
        uid: 2,
        body: comment_text
      })
      visit get_path(page_type, nodes(node_name).path)
      reply_toggles = page.all('p', text: 'Reply to this comment...')
      reply_toggles[2].click
      reply_dropzone_id = page.find('[id^=dropzone-small-reply-]')[:id] # ID begins with...
      comment_id_num = /dropzone-small-reply-(\d+)/.match(reply_dropzone_id)[1]
      # upload images
      # the <inputs> that take image uploads are hidden, so reveal them:
      Capybara.ignore_hidden_elements = false
      # upload an image in the reply comment form
      page.find('#fileinput-button-reply-' + comment_id_num).set("#{Rails.root.to_s}/public/images/pl.png")
      wait_for_ajax
      Capybara.ignore_hidden_elements = true
      page.all('a', text: 'Preview')[0].click
      assert_selector('#comment-' + comment_id_num + '-reply-section #preview img', count: 1)
    end

    test "#{page_type_string}: IMMEDIATE image DRAG & DROP into REPLY comment form" do
      Capybara.ignore_hidden_elements = false
      visit get_path(page_type, nodes(node_name).path)
      find("p", text: "Reply to this comment...").click()
      reply_preview_button = page.all('#post_comment')[0]
      # Upload the image
      drop_in_dropzone("#{Rails.root.to_s}/public/images/pl.png", ".dropzone")
      # Wait for image upload to finish
      wait_for_ajax
      Capybara.ignore_hidden_elements = true
      # Toggle preview
      reply_preview_button.click()
      # Make sure that image has been uploaded
      page.assert_selector('#preview img', count: 1)
    end

    test "#{page_type_string}: IMMEDIATE image CHOOSE ONE upload into REPLY comment form" do
      Capybara.ignore_hidden_elements = false
      visit get_path(page_type, nodes(node_name).path)
      # Open reply comment form
      find("p", text: "Reply to this comment...").click()
      first("a", text: "choose one").click() 
      reply_preview_button = page.first('a', text: 'Preview')
      Capybara.ignore_hidden_elements = false
      # Upload the image
      fileinput_element = page.first("[id^=fileinput-button-reply]")
      fileinput_element.set("#{Rails.root.to_s}/public/images/pl.png")
      Capybara.ignore_hidden_elements = true
      wait_for_ajax
      # Toggle preview
      reply_preview_button.click()
      # Make sure that image has been uploaded
      page.assert_selector('#preview img', count: 1)
    end

    # Cross-Wiring Bugs

    # sometimes if edit and reply/main comment forms are open, 
    # you drop an image into edit form, and the link will end
    # up in the other one.

    # there are many variations of this bug. this particular test involves:
    #  DRAG & DROP image upload in both:
    #    MAIN comment form
    #    EDIT comment form (.dropzone button)
    test "#{page_type_string}: image DRAG & DROP into EDIT form isn't cross-wired with MAIN form" do
      visit get_path(page_type, nodes(node_name).path)
      # make a fresh comment in the main comment form
      main_comment_form =  page.find('h4', text: /Post comment|Post Comment/).find(:xpath, '..') # title text on wikis is 'Post comment'
      # fill out the comment form
      main_comment_form
        .find('textarea')
        .click
        .fill_in with: comment_text
      # publish
      main_comment_form
        .find('button', text: 'Publish')
        .click
      page.find(".noty_body", text: "Comment Added!")
      # .dropzone is hidden, so reveal it for Capybara's finders:
      Capybara.ignore_hidden_elements = false
      # drag & drop the image. drop_in_dropzone simulates 'drop' event, see application_system_test_case.rb
      drop_in_dropzone("#{Rails.root.to_s}/public/images/pl.png", '#comments-list + div .dropzone') # this CSS selects .dropzones that belong to sibling element immediately following #comments-list. technically, there are two .dropzones in the main comment form.
      Capybara.ignore_hidden_elements = true
      wait_for_ajax
      # we need the ID of parent div that contains <p>comment_text</p>:
      comment_id = page.find('p', text: comment_text).find(:xpath, '..')[:id]
      # regex to strip the ID number out of string. ID format is comment-body-4231
      comment_id_num = /comment-body-(\d+)/.match(comment_id)[1]
      comment_dropzone_selector = '#c' + comment_id_num + 'div'
      # open the edit comment form
      page.find("#edit-comment-btn").click
      # drop into the edit comment form
      Capybara.ignore_hidden_elements = false
      drop_in_dropzone("#{Rails.root.to_s}/public/images/pl.png", comment_dropzone_selector)
      Capybara.ignore_hidden_elements = true
      wait_for_ajax
      # open the preview for the main comment form
      main_comment_form.find('a', text: 'Preview').click
      # once preview is open, the images are embedded in the page.
      # there should only be 1 image in the main comment form!
      preview_imgs = page.all('#preview img').size
      assert_equal(1, preview_imgs)
    end

    # cross-wiring test: 
    # SELECT image upload in both:
    #   EDIT form
    #   MAIN form
    test "#{page_type_string}: image SELECT upload into EDIT form isn't CROSS-WIRED with MAIN form" do
      nodes(node_name).add_comment({
        uid: 5,
        body: comment_text
      })
      nodes(node_name).add_comment({
        uid: 2,
        body: comment_text
      })
      visit get_path(page_type, nodes(node_name).path)
      # open the edit comment form:
      find("#edit-comment-btn").click
      # find the parent of edit comment's fileinput:
      comment_fileinput_parent_id = page.find('[id^=dropzone-small-edit-]')[:id] # 'begins with' CSS selector
      comment_id_num = /dropzone-small-edit-(\d+)/.match(comment_fileinput_parent_id)[1]
      # upload images
      # the <inputs> that take image uploads are hidden, so reveal them:
      Capybara.ignore_hidden_elements = false
      # upload an image in the main comment form
      page.find('#fileinput-button-main').set("#{Rails.root.to_s}/public/images/pl.png")
      wait_for_ajax
      # find edit comment's fileinput:
      page.find('#fileinput-button-edit-' + comment_id_num).set("#{Rails.root.to_s}/public/images/pl.png")
      wait_for_ajax
      Capybara.ignore_hidden_elements = true
      # click preview buttons in main and edit form
      page.find('h4', text: /Post comment|Post Comment/) # title text on wikis is 'Post comment'
        .find(:xpath, '..')
        .find('a', text: 'Preview').click
      page.find('#c' + comment_id_num + 'edit a', text: 'Preview').click
      # once preview is open, the images are embedded in the page.
      # there should be 1 image in main, and 1 image in edit
      assert_selector('#c' + comment_id_num + 'preview img', count: 1)
      assert_selector('#preview img', count: 1)
    end

    # cross-wiring test
    # SELECT image upload in both:
    #   EDIT FORM
    #   REPLY form
    test "#{page_type_string}:  image SELECT upload into EDIT form isn't CROSS-WIRED with REPLY form" do
      nodes(node_name).add_comment({
        uid: 2,
        body: comment_text
      })
      visit get_path(page_type, nodes(node_name).path)
      # find the EDIT id
      # open up the edit comment form
      page.find("#edit-comment-btn").click
      edit_comment_form_id = page.find('h4', text: 'Edit comment').find(:xpath, '..')[:id]
      # regex to strip the ID number out of string. ID format is #c1234edit
      edit_id_num = /c(\d+)edit/.match(edit_comment_form_id)[1]
      # open the edit comment form
      edit_preview_id = '#c' + edit_id_num + 'preview'
      # find the REPLY id
      page.all('p', text: 'Reply to this comment...')[0].click
      reply_dropzone_id = page.find('[id^=dropzone-small-reply-]')[:id]
      # ID begins with...
      reply_id_num = /dropzone-small-reply-(\d+)/.match(reply_dropzone_id)[1]
      # upload images
      # the <inputs> that take image uploads are hidden, so reveal them:
      Capybara.ignore_hidden_elements = false
      # upload an image in the reply comment form
      page.find('#fileinput-button-reply-' + reply_id_num).set("#{Rails.root.to_s}/public/images/pl.png")
      wait_for_ajax
      # upload an image in the edit comment form
      page.find('#fileinput-button-edit-' + edit_id_num).set("#{Rails.root.to_s}/public/images/pl.png")
      Capybara.ignore_hidden_elements = true
      wait_for_ajax
      # click preview buttons in reply and edit form
      page.find('#c' + edit_id_num + 'edit a', text: 'Preview').click
      page.first('a', text: 'Preview').click
      assert_selector('#c' + edit_id_num + 'preview img', count: 1)
      assert_selector('#preview img', count: 1)
    end

    test "#{page_type_string}: ctrl/cmd + enter comment publishing keyboard shortcut" do
      visit get_path(page_type, nodes(node_name).path)
      find("p", text: "Reply to this comment...").click()
      # Write a comment
      page.all(".text-input")[1].set("Great post!")
      page.execute_script <<-JS
        // Remove first text-input field
        $(".text-input").first().remove()
        var $textBox = $(".text-input");
        // Generate fake CTRL + Enter event
        var press = jQuery.Event("keypress");
        press.altGraphKey = false;
        press.altKey = false;
        press.bubbles = true;
        press.cancelBubble = false;
        press.cancelable = true;
        press.charCode = 10;
        press.clipboardData = undefined;
        press.ctrlKey = true;
        press.currentTarget = $textBox[0];
        press.defaultPrevented = false;
        press.detail = 0;
        press.eventPhase = 2;
        press.keyCode = 10;
        press.keyIdentifier = "";
        press.keyLocation = 0;
        press.layerX = 0;
        press.layerY = 0;
        press.metaKey = false;
        press.pageX = 0;
        press.pageY = 0;
        press.returnValue = true;
        press.shiftKey = false;
        press.srcElement = $textBox[0];
        press.target = $textBox[0];
        press.type = "keypress";
        press.view = Window;
        press.which = 10;
        // Emit fake CTRL + Enter event
        $textBox.trigger(press);
      JS
      assert_selector('#comments-list .comment', count: 2)
      assert_selector('.noty_body', text: 'Comment Added!')
    end

    test "#{page_type_string}: comment deletion" do
      visit get_path(page_type, nodes(node_name).path)
      # Create a comment
      main_comment_form =  page.find('h4', text: /Post comment|Post Comment/).find(:xpath, '..') # title text on wikis is 'Post comment'
      # fill out the comment form
      main_comment_form
        .find('textarea')
        .click
        .fill_in with: comment_text
      # publish
      main_comment_form
        .find('button', text: 'Publish')
        .click
      page.find(".noty_body", text: "Comment Added!")
      # Delete a comment
      find('.btn[data-original-title="Delete comment"]', match: :first).click()
      # Click "confirm" on modal
      page.evaluate_script('document.querySelector(".jconfirm-buttons .btn:first-of-type").click()')
      assert_selector('#comments-list .comment', count: 1)
      assert_selector('.noty_body', text: 'Comment deleted')
    end

    test "#{page_type_string}: formatting toolbar is rendered" do
      visit get_path(page_type, nodes(node_name).path)
      assert_selector('.btn[data-original-title="Bold"]', count: 1)
      assert_selector('.btn[data-original-title="Italic"]', count: 1)
      assert_selector('.btn[data-original-title="Header"]', count: 1)
      assert_selector('.btn[data-original-title="Make a link"]', count: 1)
      assert_selector('.btn[data-original-title="Upload an image"]', count: 1)
      assert_selector('.btn[data-original-title="Save"]', count: 1)
      assert_selector('.btn[data-original-title="Recover"]', count: 1)
      assert_selector('.btn[data-original-title="Help"]', count: 1)
    end

    test "#{page_type_string}: edit comment" do
      nodes(node_name).add_comment({
        uid: 2,
        body: comment_text
      })
      visit get_path(page_type, nodes(node_name).path)
      # Edit the comment
      page.execute_script <<-JS
        var comment = $(".comment")[1];
        var commentID = comment.id;
        var editCommentBtn = $(comment).find('.navbar-text #edit-comment-btn')
        // Toggle edit mode
        $(editCommentBtn).click()
        var commentTextarea = $('#' + commentID + 'text');
        $(commentTextarea).val('Updated comment.')
        var submitCommentBtn = $('#' + commentID + ' .control-group .btn-primary')[1];
        $(submitCommentBtn).click()
      JS
      message = find('.alert-success', match: :first).text
      assert_equal( "×\nComment updated.", message)
    end

    test "#{page_type_string}: react and unreact to comment" do
      visit get_path(page_type, nodes(node_name).path)
      first(".comment #dropdownMenuButton").click()
      # click on thumbs up
      find("img[src='https://github.githubassets.com/images/icons/emoji/unicode/1f44d.png']").click()
      page.assert_selector("button[data-original-title='jeff reacted with thumbs up emoji']")
      first("img[src='https://github.githubassets.com/images/icons/emoji/unicode/1f44d.png']").click()
      page.assert_no_selector("button[data-original-title='jeff reacted with thumbs up emoji'")
    end

    test "#{page_type}: multiple comment boxes, post comments" do
      if page_type == :note
        visit nodes(:note_with_multiple_comments).path
      elsif page_type == :question
        visit nodes(:question_with_multiple_comments).path
      elsif page_type == :wiki
        visit nodes(:wiki_with_multiple_comments).path + '/comments'
      end
      # there should be multiple "Reply to comment..."s on this fixture
      reply_toggles = page.all('p', text: 'Reply to this comment...')
      # extract the comment IDs from each
      comment_ids = []
      reply_toggles.each do |reply_toggle|
        id_string = reply_toggle[:id]
        comment_id = /comment-(\d+)-reply-toggle/.match(id_string)[1]
        comment_ids << comment_id
      end
      # work with just the 2nd comment
      reply_toggles[1].click 
      # open the comment form by toggling, and fill in some text
      find("div#comment-#{comment_ids[1]}-reply-section textarea.text-input").click.fill_in with: 'H'
      # open the other two comment forms
      reply_toggles[0].click
      reply_toggles[2].click
      # fill them in with text
      find("div#comment-#{comment_ids[0]}-reply-section textarea.text-input").click.fill_in with: 'A'
      find("div#comment-#{comment_ids[2]}-reply-section textarea.text-input").click.fill_in with: 'Y'
      # click the publish buttons for each in a random sequence
      [1, 2, 0].each do |number|
        find("div#comment-#{comment_ids[number]}-reply-section button", text: 'Publish').click
        wait_for_ajax
      end
      # assert that the replies went to the right comments
      assert_selector("#c" + comment_ids[0] + "show div div div p", text: 'A')
      assert_selector("#c" + comment_ids[1] + "show div div div p", text: 'H')
      assert_selector("#c" + comment_ids[2] + "show div div div p", text: 'Y')
    end
  end
end
