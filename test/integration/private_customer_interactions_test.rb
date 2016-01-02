require 'test_helper'

class PrivateCustomerInteractionsTest < ActionDispatch::IntegrationTest
  setup do
    subdomain = APP_CONFIG['subdomains']['customers']
    Capybara.app_host = "http://#{subdomain}.lvh.me:54163"
  end

  test 'should search with no results and show contextual help' do
    customer_login

    fill_in 'q', with: 'inexistent document'
    find('#q').native.send_keys :enter

    assert_equal catalog_path, current_path
    assert_page_has_no_errors!
    assert page.has_css?('#empty-search')
  end

  test 'should complete an order' do
    customer_login

    fill_in 'q', with: 'Math'
    find('#q').native.send_keys :enter

    assert_page_has_no_errors!
    assert page.has_css?('table')

    within 'table tbody' do
      assert page.has_css?('a.add_to_order')
      assert page.has_no_css?('a.remove_from_order')
      first(:css, 'a.add_to_order').click
      assert page.has_css?('a.remove_from_order')
    end

    within '.nav-collapse' do
      click_link I18n.t('view.catalog.new_order')
    end

    assert_page_has_no_errors!
    assert_equal new_order_path, current_path
    assert page.has_css?('#check_order')

    within 'div.file' do
      attach_file(
        'file_line_file',
        File.join(Rails.root, 'test', 'fixtures', 'files', 'test.pdf')
      )
    end

    assert page.has_css?('.order_line', count: 2)

    assert_difference ['Order.count', 'FileLine.count', 'OrderLine.count'] do
      click_button I18n.t(
        'helpers.submit.create', model: Order.model_name.human
      )
    end

    assert_page_has_no_errors!
    assert page.has_css?('#show_order')
  end

  test 'should do all on client calculations in new order' do
    documents(:math_book).tap do |document|
      visit add_to_order_by_code_catalog_path(document.code)

      assert_page_has_no_errors!
    end

    customer_login expected_path: new_order_path

    assert_page_has_no_errors!
    assert page.has_css?('#check_order')

    within '#check_order' do
      copies = first(:css, 'input[name$="[copies]"]').value.to_i || 0
      pages = first(:css, 'input[name$="[pages]"]').value.to_i || 0
      price_per_copy = first(:css, '.order_line')['data-price-per-copy'].to_f

      total_should_be = (copies * pages * price_per_copy).round(3)

      within 'div.order_line' do
        assert first(:css, '.money').has_content?("$#{total_should_be}")
      end

      fill_in 'order[order_lines_attributes][0][copies]', with: '5'

      new_total_should_be = (5.00 * pages * price_per_copy).round(3)

      within '.order_line' do
        assert first(:css, 'span.money').has_content?(
          "$#{new_total_should_be}"
        )
      end
    end
  end

  test 'should customize the order' do
    customer_login

    fill_in 'q', with: 'Math'
    find('#q').native.send_keys :enter

    assert_page_has_no_errors!
    assert page.has_css?('table')

    within 'table tbody' do
      assert page.has_css?('a.add_to_order')
      assert page.has_no_css?('a.remove_from_order')
      first(:css, 'a.add_to_order').click
      assert page.has_css?('a.remove_from_order')

      assert page.has_css?('a.add_to_order')
      first(:css, 'a.add_to_order').click
    end

    within '.nav-collapse' do
      click_link I18n.t('view.catalog.new_order')
    end

    assert_page_has_no_errors!
    assert_equal new_order_path, current_path
    assert page.has_css?('#check_order')

    within '#check_order' do
      assert page.has_no_css?('.document_details')
      first(:link, I18n.t('view.prints.document_details')).click
      assert page.has_css?('.document_details')
      original_price =
        first(:css, '.order_line .money').text.match(/\d+\.\d+/)[0].to_f

      assert_equal 2, page.all('.order_line').size
      first(:css, 'a[data-event="removeItem"]').click
      sleep 1 # Remove effect

      assert page.has_css?('div.order_line', count: 1)

      new_price = first(
        :css, 'div.order_line span.money'
      ).text.match(/\d+\.\d+/)[0].to_f

      assert_not_equal new_price, original_price
    end

    assert_difference ['Order.count', 'OrderLine.count'] do
      click_button I18n.t(
        'helpers.submit.create', model: Order.model_name.human
      )
    end

    assert_page_has_no_errors!
    assert page.has_css?('#show_order')
  end

  test 'should change the password and login with the correct' do
    customer_login
    customer = customers(:student_without_bonus)

    assert_page_has_no_errors!

    within '.nav.pull-right' do
      click_link customer.email
    end

    fill_in 'customer_password', with: '123456'
    fill_in 'customer_password_confirmation', with: '123456'
    click_button I18n.t('view.customers.update_profile')

    assert_equal new_customer_session_path, current_path
    assert_page_has_no_errors!

    fill_in 'customer_session_email', with: customer.email
    fill_in 'customer_session_password', with: '654321'
    click_button I18n.t('view.customer_sessions.login')

    assert_equal customer_sessions_path, current_path
    assert_page_has_no_errors!

    fill_in 'customer_session_email', with: customer.email
    fill_in 'customer_session_password', with: '123456'
    click_button I18n.t('view.customer_sessions.login')

    assert_page_has_no_errors!
  end

  test 'should add documents through tags' do
    customer_login

    click_link I18n.t('menu.tags')

    assert_page_has_no_errors!
    assert_equal catalog_tags_path, current_path

    tag = tags(:notes)
    tag_link = catalog_path(tag_id: tag.id)
    find("a[href='#{tag_link}']").click

    assert_page_has_no_errors!
    path_with_params = current_url.match /#{Capybara.app_host}(\S+)/
    assert_equal catalog_path(tag_id: tag.id), path_with_params[1]

    within 'table tbody' do
      assert page.has_no_css?('a.remove_from_order')

      tag.documents_count.times do
        assert page.has_css?('a.add_to_order')
        first(:css, 'a.add_to_order').click
        assert page.has_css?('a.remove_from_order')
      end

      assert page.has_no_css?('a.add_from_order')
    end

    sleep 2

    within '.nav-collapse' do
      click_link I18n.t('view.catalog.new_order')
    end

    sleep 2
    assert_equal new_order_path, current_path
    assert_page_has_no_errors!

    page.all 'div.order_line', count: tag.reload.documents_count
  end

  private

  def customer_login(options = {})
    options.reverse_merge!(
      customer_id: :student_without_bonus,
      expected_path: catalog_path
    )

    visit new_customer_session_path

    assert_page_has_no_errors!

    customers(options[:customer_id]).tap do |customer|
      fill_in I18n.t('authlogic.attributes.customer_session.email'),
              with: customer.email
      fill_in I18n.t('authlogic.attributes.customer_session.password'),
              with: "#{options[:customer_id]}123"
    end

    click_button I18n.t('view.customer_sessions.login')

    assert_page_has_no_errors!
    assert_equal options[:expected_path], current_path

    show_collapse_menu_if_needed
  end
end
