require 'browser_helper'

RSpec.feature 'Projects', type: :feature, js: true do
  let!(:admin_user) { create(:admin_user, :with_home) }
  let!(:user) { create(:confirmed_user, :with_home, login: 'Jane') }
  let(:project) { user.home_project }

  scenario 'project show' do
    login user
    visit project_show_path(project: project)
    expect(page).to have_text(/Packages .*0/)
    expect(page).to have_text('This project does not contain any packages')
    expect(page).to have_text(project.description)
    expect(page).to have_css('h3', text: project.title)
  end

  describe 'creating packages in projects owned by user, eg. home projects' do
    let(:very_long_description) { Faker::Lorem.paragraph(sentence_count: 20) }

    before do
      login user
      visit project_show_path(project: user.home_project)
      click_link('Create Package')
      expect(page).to have_text("Create Package for #{user.home_project_name}")
    end

    scenario 'with invalid data (validation fails)' do
      fill_in 'name', with: 'cool stuff'
      click_button('Create')

      expect(page).to have_text("Invalid package name: 'cool stuff'")
      expect(page.current_path).to eq("/project/new_package/#{user.home_project_name}")
    end

    scenario 'that already exists' do
      create(:package, name: 'coolstuff', project: user.home_project)

      fill_in 'name', with: 'coolstuff'
      click_button('Create')

      expect(page).to have_text("Package 'coolstuff' already exists in project '#{user.home_project_name}'")
      expect(page.current_path).to eq("/project/new_package/#{user.home_project_name}")
    end
  end

  describe 'creating packages in projects not owned by user, eg. global namespace' do
    let(:other_user) { create(:confirmed_user, login: 'other_user') }
    let(:global_project) { create(:project, name: 'global_project') }

    scenario 'as non-admin user' do
      login other_user
      visit project_show_path(project: global_project)
      expect(page).not_to have_link('Create package')

      # Use direct path instead
      visit "/project/new_package/#{global_project}"

      expect(page).to have_text('Sorry, you are not authorized to update this Project')
      expect(page.current_path).to eq(root_path)
    end

    scenario 'as admin' do
      login admin_user
      visit project_show_path(project: global_project)
      click_link('Create Package')

      fill_in 'name', with: 'coolstuff'
      click_button('Create')

      expect(page).to have_text("Package 'coolstuff' was created successfully")
      expect(page.current_path).to eq(package_show_path(project: global_project.to_s, package: 'coolstuff'))
    end
  end

  describe 'subprojects' do
    scenario 'create a subproject' do
      login user
      visit project_show_path(user.home_project)
      click_link('Subprojects')

      expect(page).to have_text('This project has no subprojects')
      click_link('Add New Subproject')
      fill_in 'project_name', with: 'coolstuff'
      click_button('Accept')
      expect(page).to have_content("Project '#{user.home_project_name}:coolstuff' was created successfully")

      expect(page.current_path).to match(project_show_path(project: "#{user.home_project_name}:coolstuff"))
      expect(find('#project-title').text).to eq("#{user.home_project_name}:coolstuff")
    end
  end

  describe 'locked projects' do
    let!(:locked_project) { create(:locked_project, name: 'locked_project') }
    let!(:relationship) { create(:relationship, project: locked_project, user: user) }

    before do
      login user
      visit project_show_path(project: locked_project.name)
    end

    scenario 'unlock' do
      click_link('Unlock Project')
      fill_in 'comment', with: 'Freedom at last!'
      click_button('Accept')
      expect(page).to have_content('Successfully unlocked project')

      visit project_show_path(project: locked_project.name)
      expect(page).not_to have_text('is locked')
    end

    scenario 'fail to unlock' do
      allow_any_instance_of(Project).to receive(:can_be_unlocked?).and_return(false)

      click_link('Unlock Project')
      fill_in 'comment', with: 'Freedom at last!'
      click_button('Accept')
      expect(page).to have_content("Project can't be unlocked")

      visit project_show_path(project: locked_project.name)
      expect(page).to have_text('is locked')
    end
  end

  describe 'branching' do
    let(:other_user) { create(:confirmed_user, :with_home, login: 'other_user') }
    let!(:package_of_another_project) { create(:package_with_file, name: 'branch_test_package', project: other_user.home_project) }

    before do
      login user
      visit project_show_path(project)
      click_link('Branch Existing Package')
    end

    scenario 'an existing package' do
      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)
      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('Successfully branched package')
      expect(page.current_path).to eq('/package/show/home:Jane/branch_test_package')
    end

    scenario 'an existing package, but chose a different target package name' do
      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)
      fill_in('Branch package name', with: 'some_different_name')
      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('Successfully branched package')
      expect(page.current_path).to eq("/package/show/#{user.home_project_name}/some_different_name")
    end

    scenario 'an existing package to an invalid target package or project' do
      skip_if_bootstrap

      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)
      fill_in('Branch package name', with: 'something/illegal')
      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('Failed to branch: Validation failed: Name is illegal')
      expect(page.current_path).to eq('/project/new_package_branch/home:Jane')
    end

    scenario 'an existing package were the target package already exists' do
      create(:package_with_file, name: package_of_another_project.name, project: user.home_project)

      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)
      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('You have already branched this package')
      expect(page.current_path).to eq('/package/show/home:Jane/branch_test_package')
    end

    scenario 'a package with disabled access flag' do
      skip_if_bootstrap

      create(:access_flag, status: 'disable', project: other_user.home_project)

      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)
      fill_in('Branch package name', with: 'some_different_name')
      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('Failed to branch: Package does not exist.')
      expect(page.current_path).to eq('/project/new_package_branch/home:Jane')
    end

    scenario 'a package with disabled sourceaccess flag' do
      skip_if_bootstrap

      create(:sourceaccess_flag, status: 'disable', project: other_user.home_project)

      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)
      fill_in('Branch package name', with: 'some_different_name')
      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('Sorry, you are not authorized to branch this Package.')
      expect(page.current_path).to eq('/project/new_package_branch/home:Jane')
    end

    scenario 'a package and select current revision' do
      skip_if_bootstrap

      fill_in('linked_project', with: other_user.home_project_name)
      fill_in('linked_package', with: package_of_another_project.name)

      find("input[id='current_revision']").set(true)

      # This needs global write through
      click_button('Accept')

      expect(page).to have_text('Successfully branched package')
      expect(page.current_path).to eq('/package/show/home:Jane/branch_test_package')

      visit package_show_path('home:Jane', 'branch_test_package', expand: 0)
      click_link('_link')

      expect(page).to have_xpath(".//span[@class='cm-attribute' and text()='rev']")
    end
  end

  describe 'maintenance projects' do
    scenario 'creating a maintenance project' do
      skip_if_bootstrap

      login(admin_user)
      visit project_show_path(project)

      click_link('Attributes')
      click_link('Add a new attribute')
      select('OBS:MaintenanceProject')
      click_button('Add')

      expect(page).to have_text('Attribute was successfully created.')
      expect(find('table tr td:first-child')).to have_text('OBS:MaintenanceProject')
    end
  end

  describe 'maintained projects' do
    let(:maintenance_project) { create(:maintenance_project, name: 'maintenance_project') }

    scenario 'creating a maintened project' do
      skip_if_bootstrap

      login(admin_user)
      visit project_show_path(maintenance_project)

      click_link('Maintained Projects')
      click_link('Add project to maintenance')
      fill_in('Project to maintain:', with: project.name)
      expect(page).to have_text('1 result is available')
      click_button('Accept')

      expect(page).to have_text("Added #{project.name} to maintenance")
      expect(find('table#maintained_projects_table td:first-child')).to have_text(project.name)
    end
  end

  describe 'monitor' do
    let!(:project) { create(:project, name: 'TestProject') }
    let!(:package1) { create(:package, project: project, name: 'TestPackage') }
    let!(:package2) { create(:package, project: project, name: 'SecondPackage') }
    let!(:repository1) { create(:repository, project: project, name: 'openSUSE_Tumbleweed', architectures: ['x86_64', 'i586']) }
    let!(:repository2) { create(:repository, project: project, name: 'openSUSE_Leap_42.3', architectures: ['x86_64', 'i586']) }
    let!(:repository3) { create(:repository, project: project, name: 'openSUSE_Leap_42.2', architectures: ['x86_64', 'i586']) }

    let(:build_results_xml) do
      <<-XML
      <resultlist state="dc66a487ea4d97b4f157d075a0e747b9">
        <result project="TestProject" repository="openSUSE_Tumbleweed" arch="x86_64" code="published" state="published">
          <status package="SecondPackage" code="broken">
            <details>no source uploaded</details>
          </status>
          <status package="TestPackage" code="broken">
            <details>no source uploaded</details>
          </status>
        </result>
        <result project="TestProject" repository="openSUSE_Leap_42.3" arch="x86_64" code="published" state="published">
          <status package="SecondPackage" code="broken">
            <details>no source uploaded</details>
          </status>
          <status package="TestPackage" code="broken">
            <details>no source uploaded</details>
          </status>
        </result>
        <result project="TestProject" repository="openSUSE_Leap_42.2" arch="x86_64" code="published" state="published">
          <status package="SecondPackage" code="broken">
            <details>no source uploaded</details>
          </status>
          <status package="TestPackage" code="broken">
            <details>no source uploaded</details>
          </status>
        </result>
        <result project="TestProject" repository="openSUSE_Tumbleweed" arch="i586" code="published" state="published">
          <status package="SecondPackage" code="broken">
            <details>no source uploaded</details>
          </status>
          <status package="TestPackage" code="broken">
            <details>no source uploaded</details>
          </status>
        </result>
        <result project="TestProject" repository="openSUSE_Leap_42.3" arch="i586" code="published" state="published">
          <status package="SecondPackage" code="broken">
            <details>no source uploaded</details>
          </status>
          <status package="TestPackage" code="broken">
            <details>no source uploaded</details>
          </status>
        </result>
        <result project="TestProject" repository="openSUSE_Leap_42.2" arch="i586" code="published" state="published">
          <status package="SecondPackage" code="broken">
            <details>no source uploaded</details>
          </status>
          <status package="TestPackage" code="broken">
            <details>no source uploaded</details>
          </status>
        </result>
      </resultlist>
      XML
    end

    before do
      login admin_user
      allow(Backend::Api::BuildResults::Status).to receive(:result_swiss_knife).and_return(build_results_xml)
      visit project_monitor_path(project.name)
      expect(page).to have_text('Monitor')
    end

    scenario 'filtering build results by package name' do
      skip_if_bootstrap # this is now handled by datatables, we don't need to test it
      fill_in 'pkgname', with: package1.name
      click_button 'Filter:'

      build_status_table = find('table.buildstatus')
      expect(build_status_table).to have_text(package1.name)
      expect(build_status_table).not_to have_text(package2.name)
    end

    scenario 'filtering build results by architecture' do
      skip_if_bootstrap
      find('#archlink').click
      uncheck 'arch_x86_64'
      click_button 'Filter:'

      build_status_table = find('table.buildstatus')
      expect(build_status_table).to have_text('i586')
      expect(build_status_table).not_to have_text('x86_64')
    end

    scenario 'filtering build results by repository' do
      skip_if_bootstrap
      find('#repolink').click
      uncheck 'repo_openSUSE_Leap_42_2'
      uncheck 'repo_openSUSE_Leap_42_3'
      click_button 'Filter:'

      build_status_table = find('table.buildstatus')
      expect(build_status_table).not_to have_text('openSUSE_Leap_42.2')
      expect(build_status_table).not_to have_text('openSUSE_Leap_42.3')
      expect(build_status_table).to have_text('openSUSE_Tumbleweed')
    end

    scenario 'filtering build results by last build' do
      skip_if_bootstrap # we don't support this anymore
      check 'lastbuild'
      click_button 'Filter:'

      build_status_table = find('table.buildstatus')
      expect(build_status_table).to have_text('openSUSE_Leap_42.2')
      expect(build_status_table).to have_text('openSUSE_Leap_42.3')
      expect(build_status_table).to have_text('openSUSE_Tumbleweed')
      expect(build_status_table).to have_text('i586')
      expect(build_status_table).to have_text('x86_64')
      expect(build_status_table).to have_text(package1.name)
      expect(build_status_table).to have_text(package2.name)
    end
  end
end
